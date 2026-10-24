# frozen_string_literal: true

require "erb"
require "fileutils"
require "open3"

module OpenLanes
  module Engine
    module Verification
      # What the engine does with a verification once chewie has signed, or
      # once the app would not start (M1, M14, M15). chewie only writes files
      # in its round's folder; everything that leaves the machine is done
      # here, because the comment links the screenshot by the SHA of a commit
      # only the engine may make, and `ready-to-merge` waits for a CI run that
      # commit itself starts.
      #
      # Rejecting: commit the failing step's PNG, comment with it, label
      # `review-rejected`, then send the plan to 🔴 and mail the comment to
      # whoever handles 🔴, through {PrOutcomes}, exactly as a person's
      # rejection on GitHub is handled.
      #
      # Passing: commit `final.png` ({#pass}), then, each time the engine
      # asks ({#settle}), wait for green CI, run the coverage gate and label
      # `ready-to-merge`. Merging is not here: plan 033 merges in agent mode,
      # and in human mode the person does (M4).
      class Outcome
        # What one step did.
        #
        # @!attribute [r] kind
        #   @return [Symbol] :rejected, :committed (passed and pushed, CI not read yet),
        #     :waiting (CI pending), or :ready (`ready-to-merge` applied)
        # @!attribute [r] note
        #   @return [String] for the attempt and the log
        # @!attribute [r] to
        #   @return [Symbol, nil] the state the folder moved to
        # @!attribute [r] sha
        #   @return [String, nil] the verification commit, on :committed
        Result = Data.define(:kind, :note, :to, :sha) do
          def initialize(to: nil, sha: nil, **rest) = super
        end

        # What one look at a verified pull request found, and nothing more:
        # {#look} reads GitHub and runs the coverage gate, which may take
        # minutes, so it runs off the dispatcher's thread; {#settle} acts on
        # it (labels, rejects, renames, mails) back on that thread, where
        # every other lifecycle change happens.
        #
        # @!attribute [r] ci
        #   @return [Symbol] :labelled (already `ready-to-merge`), :registering
        #     (no checks yet, within {NO_CHECKS_GRACE}), or a {Vcs::CiGate} verdict
        # @!attribute [r] verdict
        #   @return [CoverageGate::Verdict, nil] the gate's, once CI is green
        Look = Data.define(:ci, :verdict) do
          def initialize(verdict: nil, **rest) = super
        end

        # Who the comment and the harness's own signature are from.
        AGENT = "chewie-verifier"

        # A signature that counts as a rejection: its note starts with the
        # word, as `rejected`, `rejected 1/2` (hansolo) or `rejected: …` (the
        # harness signing for chewie). Anchored rather than searched for: an
        # approving note that says "nothing to reject" is not a rejection, and
        # counting it would reach the arbitrator a round early. Spelled once,
        # in {OpenLanes::Arbitration::Counter}, which does the counting.
        REJECTION = OpenLanes::Arbitration::Counter::REJECTION

        # How long after the verification commit zero checks still means
        # "CI has not registered yet" rather than "this project has no CI".
        # Right after {#pass} pushes `final.png` the new head can report no
        # checks for a while; {Vcs::Review} counts none as green, so without
        # this window `ready-to-merge` could go on before the run that commit
        # starts. Past it, none is taken at its word, or a project with no CI
        # would wait forever.
        NO_CHECKS_GRACE = 5 * 60

        # Lines of a withheld coverage run quoted in the comment.
        TAIL = CoverageGate::TAIL

        # What the builders are told when the branch's `.openlanes.yml` has
        # no `coverage:` section. A plain rejection would only say the gate
        # withheld, and the builder would go looking for a defect; this names
        # the one thing to write, in both shapes, so the next round writes it.
        # It is signed "sent back", not "rejected" ({REJECTION}), because
        # this one does not count.
        SETUP = <<~MARKDOWN
          Coverage is not declared yet: this branch's `.openlanes.yml` has no `coverage:` section, so the coverage gate had nothing to measure and `ready-to-merge` waits on it.

          Add a `coverage:` section to `.openlanes.yml` for this stack, in one of two shapes. `command` (runs the whole suite) and `minimum` (the lowest line percentage that merges) are required in both.

          A command that prints the line percentage:

          ```yaml
          coverage:
            command: bundle exec rspec
            report_command: jq '.total.lines.percent' coverage/coverage.json
            minimum: 95
          ```

          Or a report file, in one of the formats the gate reads:

          ```yaml
          coverage:
            command: npm test -- --coverage
            report: coverage/lcov.info
            format: lcov    # lcov | cobertura | istanbul | simplecov
            minimum: 95
          ```

          This send-back is a setup gap, not a defect, and does not count against `merge.max_rejections`.
        MARKDOWN

        # @param root [String] the main checkout, which the PNG's link is relative to
        # @param publisher [OpenLanes::Vcs::Publisher]
        # @param github [OpenLanes::Vcs::GitHub]
        # @param outcomes [OpenLanes::Engine::PrOutcomes] moves to 🔴 and mails
        # @param agents [OpenLanes::Agents::Registry] whose rejections count
        # @param review [OpenLanes::Vcs::Review]
        # @param coverage_gate [#call]
        # @param max_rejections [Integer, #call] see {Config#max_rejections};
        #   a callable is asked at every rejection, so a quality answered or
        #   edited mid-run moves the cap when it moves the verdict
        # @param arbitration [#call] given `plan:, count:, max:` at the cap
        # @param screenshots [#call] a round's folder to a {Screenshots}
        # @param clock [#call] the time now, for {NO_CHECKS_GRACE}
        def initialize(root:, publisher:, github:, outcomes:, agents:, review: Vcs::Review.new(github:),
          coverage_gate: CoverageGate.new, max_rejections: Config::DEFAULT_MAX_REJECTIONS,
          arbitration: Arbitration, screenshots: ->(dir) { Screenshots.new(dir:) }, clock: -> { Clock::System.now })
          @root = root
          @publisher = publisher
          @github = github
          @outcomes = outcomes
          @agents = agents
          @review = review
          @gate = coverage_gate
          @max = max_rejections
          @arbitration = arbitration
          @screenshots = screenshots
          @clock = clock
          @verdicts = {}
        end

        # @param checkout [OpenLanes::Vcs::Worktree::Checkout] the plan's
        # @param plan [OpenLanes::Plans::Subject] read fresh, in the main checkout
        # @param pull [OpenLanes::Plans::PullRequest] the plan's open pull request
        # @param round [Round]
        # @param why [String, nil] Markdown saying what failed when chewie's
        #   report cannot: the app that did not start, red CI, the coverage gate
        # @param counted [Boolean] false for a send-back that is a setup gap
        #   rather than a defect ({SETUP}): it goes to the builders like any
        #   rejection, but is not signed as one, so `merge.max_rejections`
        #   never reaches the arbitrator over a missing config section
        # @return [Result]
        def reject(checkout:, plan:, pull:, round:, why: nil, counted: true)
          round.make!
          report = round.report || Report.new
          if why
            # Over a verified report too (CI or coverage failing after it), so
            # the round reads as rejected and a later 🧪 gets a new round
            # rather than being taken for one still waiting on CI.
            write_report(round, why) unless report.verdict == :rejected
            sign_for_chewie(plan, round, why, counted:)
          end
          kept = keep(round, failing_step: report.step)
          sha, committed = commit(checkout, plan, round, "rejected")
          png = kept.find { File.basename(it) == report.screenshot }
          body = comment(plan:, round:, report:, why:, link: link(pull, sha, png), committed:, counted:)
          number = number_of(pull)
          @github.comment(number:, body:, repo: Vcs::GitHub.repo_of(pull.url))
          labelled = @review.call(pr: pull.url || number, label: Plans::ReviewLabel::REJECTED)
          send_back(plan, pull, body, labelled, counted:)
        end

        # chewie verified it: keep `final.png`, and push it.
        #
        # A commit that failed is sent back rather than reported as
        # committed: {#settle} would otherwise read the old head's CI and
        # label it ready with no `final.png` on the branch, and the missing
        # evidence would go unnoticed. It is a send-back, not a counted
        # rejection, because the code may be fine; what is wrong is the
        # checkout (a stray file, a push that would not go). Nothing past
        # this point reads CI for a round whose push failed.
        #
        # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
        # @param plan [OpenLanes::Plans::Subject]
        # @param pull [OpenLanes::Plans::PullRequest] the plan's open pull request
        # @param round [Round]
        # @return [Result] :committed, the folder staying 🧪 until {#settle};
        #   :rejected when `final.png` could not be committed
        def pass(checkout:, plan:, pull:, round:)
          keep(round, failing_step: nil)
          sha, committed, failure = commit(checkout, plan, round, "verified")
          return uncommitted(checkout:, plan:, pull:, round:, failure:) if failure

          pushed = sha ? "#{Screenshots::FINAL} pushed in #{sha[0, 7]}" : committed
          Result.new(kind: :committed, note: "verified PR ##{number_of(pull)}; #{pushed}; waiting on CI", sha:)
        end

        # Read what decides a verified pull request: its labels, its CI and,
        # once CI is green, the coverage gate. Changes nothing in the plan,
        # on GitHub or in the round, so it is safe off the dispatcher's
        # thread (the gate writes only what the project's suite writes).
        #
        # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
        # @param plan [OpenLanes::Plans::Subject]
        # @param pull [OpenLanes::Plans::PullRequest] the plan's open pull request
        # @param round [Round] the verified round
        # @return [Look]
        def look(checkout:, plan:, pull:, round:)
          number = number_of(pull)
          repo = Vcs::GitHub.repo_of(pull.url)
          return Look.new(ci: :labelled) if labelled_ready?(number, repo)

          ci = Vcs::CiGate.verdict(@github.checks(number:, repo:))
          ci = :registering if ci == :none && registering?(round)
          return Look.new(ci:) if %i[registering pending red].include?(ci)

          Look.new(ci:, verdict: gate_verdict(checkout, plan, round))
        end

        # Act on one look at a verified pull request, asked again until it
        # is labelled or rejected: CI pending waits, and so do no checks at
        # all within {NO_CHECKS_GRACE} of the verification; CI red or the
        # coverage gate withholding rejects; otherwise `ready-to-merge` goes on.
        #
        # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
        # @param plan [OpenLanes::Plans::Subject]
        # @param pull [OpenLanes::Plans::PullRequest] the plan's open pull request
        # @param round [Round] the verified round
        # @param seen [Look, nil] what {#look} found; nil looks now
        # @return [Result]
        def settle(checkout:, plan:, pull:, round:, seen: nil)
          seen ||= look(checkout:, plan:, pull:, round:)
          number = number_of(pull)
          case seen.ci
          when :labelled then ready(plan, number, "already #{Plans::ReviewLabel::READY_TO_MERGE}")
          when :registering then Result.new(kind: :waiting, note: "🧪 no checks yet on PR ##{number}; waiting for CI to start")
          when :pending then Result.new(kind: :waiting, note: "🧪 waiting on CI for PR ##{number}")
          when :red then reject(checkout:, plan:, pull:, round:, why: "CI is red on PR ##{number} after verification.")
          else gated(checkout:, plan:, pull:, round:, verdict: seen.verdict)
          end
        end

        # A `review-ok-not-perfect` pull request under `high` (R4), sent back
        # to the builders without verifying it. Signed and counted as a
        # rejection: the builders may answer every comment with a rebuttal
        # and no change, hansolo may label it the same again, and an
        # uncounted send-back would then go round for ever, never reaching
        # `merge.max_rejections` or the arbitrator.
        #
        # @param plan [OpenLanes::Plans::Subject] read fresh, at 👀
        # @param pull [OpenLanes::Plans::PullRequest] the plan's open pull request
        # @return [Result]
        def send_back_for_quality(plan:, pull:)
          why = "PR ##{number_of(pull)} is labelled #{ON_QUALITY.name}, and desired_codebase_quality is high"
          sign_for_chewie(plan, Verification.round_for(plan.feature.path), why, counted: true)
          body = <<~MARKDOWN
            #{why}: reply in the thread of every review comment that is not ✅, with a fix or a backed-up rebuttal (R4).
          MARKDOWN
          send_back(plan, pull, body, nil, counted: true)
        end

        # Why this checkout is not the pull request's code, asked before
        # chewie is started on it ({Driver#hand_off}); {Vcs::Publisher#commit_plan}
        # asks again before the screenshots are pushed.
        #
        # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
        # @param pull [OpenLanes::Plans::PullRequest]
        # @return [String, nil] nil when the pull request is built from the checkout's branch
        def mismatch(checkout:, pull:) = @publisher.branch_mismatch(pull, checkout, refused: "verification refused")

        # @param pull [OpenLanes::Plans::PullRequest]
        # @return [Array<String>] the pull request's labels, as GitHub has them now
        # @raise [OpenLanes::Error] when GitHub cannot be asked
        def labels(pull) = @github.labels(number: number_of(pull), repo: Vcs::GitHub.repo_of(pull.url))

        # Every rejection of this plan toward the cap, hansolo's and chewie's
        # together (M6), as {OpenLanes::Arbitration::Counter} counts them.
        #
        # @param plan [OpenLanes::Plans::Subject]
        # @return [Integer]
        def rejections(plan) = OpenLanes::Arbitration.counter(agents: @agents).call(plan)

        private

        # @return [Result]
        def gated(checkout:, plan:, pull:, round:, verdict:)
          return reject(checkout:, plan:, pull:, round:, why: SETUP, counted: false) if verdict.unconfigured?
          return reject(checkout:, plan:, pull:, round:, why: withheld(verdict)) if verdict.withheld?

          result = @review.call(pr: pull.url || number_of(pull), label: Plans::ReviewLabel::READY_TO_MERGE)
          return Result.new(kind: :waiting, note: "🧪 #{Plans::ReviewLabel::READY_TO_MERGE} refused: #{result.reason}") if result.refused?

          # Nothing merges here: the plan goes on to 🏁, where palpatine
          # weighs each pull request and {Engine::Merging} acts on it (P1).
          ready(plan, number_of(pull), "#{Plans::ReviewLabel::READY_TO_MERGE}: #{verdict.reason}")
        end

        # The coverage gate's verdict on this round's commit, run once. A
        # refused `ready-to-merge` (CI flipping to pending between two reads)
        # answers :waiting, and without this every poll after it would run
        # the project's whole suite again over code that has not changed. A
        # new commit on the branch is a new key, so it is measured afresh; a
        # head that cannot be read is never cached.
        #
        # @return [OpenLanes::Engine::CoverageGate::Verdict]
        def gate_verdict(checkout, plan, round)
          head = head_of(checkout) or return @gate.call(checkout:)

          @verdicts[[plan.feature.ordinal.to_s, round.number, head]] ||= @gate.call(checkout:)
        end

        # @return [String, nil] the checkout's HEAD, nil when git cannot say
        def head_of(checkout)
          out, status = Open3.capture2("git", "-C", checkout.path.to_s, "rev-parse", "HEAD", err: File::NULL)
          status.success? ? out.strip : nil
        rescue SystemCallError
          nil
        end

        # Whether the verification commit is recent enough that CI may not
        # have registered on it yet. Timed from the round's publication
        # record, written just after the push, or failing that its report;
        # read from disk rather than remembered, so a restarted engine keeps
        # the same window.
        #
        # @return [Boolean]
        def registering?(round)
          path = round && [round.published_path, round.report_path].find { File.exist?(it) }
          return false unless path

          @clock.call - File.mtime(path) < NO_CHECKS_GRACE
        end

        # @return [Result]
        # `ready-to-merge` is on. Once every open pull request of the plan
        # carries it, the plan is 🏁 Completed (P1), and palpatine is next.
        #
        # @return [Result]
        def ready(plan, number, why)
          # Waiting, not ready: the look comes round again, and finds this
          # one labelled and the others perhaps labelled by then.
          unless every_pull_ready?(plan, number)
            return Result.new(kind: :waiting, note: "PR ##{number} #{why}; waiting for the plan's other pull requests")
          end

          unless plan.machine.may?(:completed)
            why_not = Plans::STATUS_BY_KEY.fetch(:completed).violation(plan) || "#{plan.status} cannot become 🏁"
            return Result.new(kind: :ready, note: "PR ##{number} #{why}; stays 🧪: #{why_not}")
          end

          plan.machine.promote!(:completed)
          Result.new(kind: :ready, to: :completed, note: "PR ##{number} #{why}; on to 🏁, for palpatine to weigh")
        end

        # @param labelled [Integer] the pull request just labelled, not asked again
        # @return [Boolean]
        def every_pull_ready?(plan, labelled)
          plan.pull_requests.select(&:open?).all? do |pull|
            next true if number_of(pull) == labelled

            @github.labels(number: number_of(pull), repo: Vcs::GitHub.repo_of(pull.url)).include?(Plans::ReviewLabel::READY_TO_MERGE.name)
          end
        end

        # @return [Boolean]
        def labelled_ready?(number, repo) = @github.labels(number:, repo:).include?(Plans::ReviewLabel::READY_TO_MERGE.name)

        # @return [String]
        def withheld(verdict)
          lines = ["The coverage gate withheld #{Plans::ReviewLabel::READY_TO_MERGE}: #{verdict.reason}."]
          lines.push("", "```text", *verdict.output.last(TAIL), "```") unless verdict.output.empty?
          lines.join("\n")
        end

        # Only what the round is allowed to keep, minus the engine's own note
        # about the app, which names this machine's ports and is no part of
        # the record.
        #
        # @return [Array<String>] the kept images
        #
        # A round holding an image that is not PNG has those images deleted
        # before anything else: both callers commit the round's folder whole,
        # so an image merely "not kept" would be published all the same,
        # together with every step screenshot {Screenshots#prepare} would
        # have pruned. The PNGs then go through {Screenshots#prepare} as
        # usual, so the evidence that can be shown still is.
        def keep(round, failing_step:)
          return [] unless File.directory?(round.dir)

          FileUtils.rm_f(File.join(round.dir, Round::APP_NOTE))
          shots = @screenshots.call(round.dir)
          begin
            shots.prepare(failing_step:)
          rescue Screenshots::Refused => e
            removed = shots.discard_foreign!
            UI.log("#{e.message}; deleted #{removed.join(", ")} rather than publish them", level: :warn)
            shots.prepare(failing_step:)
          end
        end

        # @return [Array(String, String, String)] the SHA, nil when nothing
        #   was committed; what to say about it; and why the commit failed,
        #   nil when it did not
        def commit(checkout, plan, round, verdict)
          message = "Verify #{plan.feature.ordinal}, round #{round.number}: #{verdict}"
          sha = @publisher.commit_plan(checkout:, plan:, message:)
          [sha, sha ? "committed #{sha[0, 7]}" : "nothing committed on a dry run", nil]
        rescue Error => e
          [nil, "not committed: #{e.message}", e.message]
        end

        # @return [Result] the send-back for a verified round whose evidence
        #   never reached the branch, its note saying so first. A push that
        #   failed after a local commit lands here too: the commit waits in
        #   the checkout, and the builders' next publish carries it.
        def uncommitted(checkout:, plan:, pull:, round:, failure:)
          why = "Verified, but #{Screenshots::FINAL} never reached the pull request, so it carries no evidence: #{failure}"
          result = reject(checkout:, plan:, pull:, round:, why:, counted: false)
          result.with(note: "verified PR ##{number_of(pull)} but NOT published (#{failure}); #{result.note}")
        end

        # The engine writes the report chewie never got to write.
        #
        # @return [void]
        def write_report(round, why)
          File.write(round.report_path, <<~MARKDOWN)
            # Verification, round #{round.number}

            Verdict: rejected

            Written by the engine: the round failed where chewie-verifier could not say so.

            #{why}
          MARKDOWN
        end

        # A rejection chewie did not sign (the app, CI, the coverage gate)
        # still counts against the cap. A setup send-back is signed too, so
        # the round has its record, but as "sent back", which {#rejections}
        # does not count.
        #
        # @return [void]
        def sign_for_chewie(plan, round, why, counted:)
          first = why.lines.first.to_s.strip.delete("()").sub(/[.:]\z/, "")
          Plans::PlanState.for(plan.feature.path)
                          .sign!(agent: AGENT,
                            round: round.number,
                            status: "Completed",
                            note: "#{counted ? "rejected" : "sent back"}: #{first}; signed by harness")
        end

        # @return [Result]
        def send_back(plan, pull, body, labelled, counted:)
          count = rejections(plan)
          max = @max.respond_to?(:call) ? @max.call : @max
          tally = counted ? "rejected #{count} of #{max}" : "sent back for setup, not counted (#{count} of #{max})"
          @arbitration.call(plan:, count:, max:) if counted && count >= max
          # Asked before the move: the rename leaves +plan+'s path behind.
          last_chance = after_go?(plan, count, counted)
          moved = @outcomes.apply(PrWatch::Outcome.new(plan: plan.feature.ordinal.to_s,
            pr: number_of(pull),
            kind: :rejected,
            comments: [{ author: AGENT, url: pull.url.to_s, body: }]))
          label = if labelled.nil? then "labels left as hansolo set them"
                  elsif labelled.refused? then "#{Plans::ReviewLabel::REJECTED} refused: #{labelled.reason}"
                  else Plans::ReviewLabel::REJECTED.name
                  end
          Result.new(kind: :rejected,
            note: "verification #{counted ? "rejected" : "sent back"} PR ##{number_of(pull)}, #{tally}; #{label}" \
                  "#{"; #{moved.note}" if moved}#{"; blocked: the last verification after a go ruling failed" if (blocked = last_chance && block(plan))}",
            to: blocked ? :blocked : moved&.to)
        end

        # The first counted rejection after a `cap/go` ruling (M8): the
        # arbitrator already gave the plan its last chance, so it goes to a
        # person rather than back to the builders.
        #
        # @return [Boolean]
        def after_go?(plan, count, counted)
          return false unless counted && count == 1

          Plans::PlanState.for(plan.feature.path).rulings.select { it["kind"] == "cap" }.last&.fetch("outcome", nil) == "go"
        end

        # @return [Boolean] whether the plan reached ⭕️
        def block(plan)
          subject = Plans::Tree.new(dir: File.dirname(plan.feature.path)).find(plan.feature.ordinal.to_s) or return false
          OpenLanes::Arbitration.block(subject, <<~MD)
            # Blocked

            ## B1 Verification failed again after the arbitrator ruled go at the cap

            The arbitrator gave this plan one last verification, and it failed. Read chewie's comment on the pull request.

            a) Send it back to the builders for one more round. (Recommended)
            b) Close the pull request and replan.
          MD
        end

        # @return [String] Markdown
        def comment(plan:, round:, report:, why:, link:, committed:, counted:)
          lines = ["### 🧪 #{AGENT}: #{counted ? "rejected" : "sent back for setup"}, verification round #{round.number}", ""]
          if why
            lines << why
          else
            lines << "**Step #{report.step || "?"}:** #{report.what || "see #{round.relative}/#{Round::REPORT}"}" << ""
            lines << "- **Expected:** #{report.expected || "not reported"}"
            lines << "- **Seen:** #{report.seen || "not reported"}"
          end
          lines << "" << "![#{report.screenshot}](#{link})" if link
          lines << "" << "The screenshots were #{committed}." unless link || why
          lines << "" << "Plan #{plan.feature.ordinal}. How to test is in the pull request's description."
          lines.join("\n")
        end

        # M14: by commit SHA, so the image renders in a private repository
        # too. Every byte of the path is escaped: plan folders carry emoji,
        # `━` and `❯`, and one unescaped byte is a broken image.
        #
        # @return [String, nil]
        def link(pull, sha, png)
          repo = Vcs::GitHub.repo_of(pull.url)
          return nil unless sha && png && repo

          path = Pathname(File.realpath(png)).relative_path_from(Pathname(File.realpath(@root))).to_s
          "https://github.com/#{repo}/blob/#{sha}/#{path.split("/").map { ERB::Util.url_encode(it) }.join("/")}?raw=true"
        end

        # @return [Integer]
        def number_of(pull) = Vcs::GitHub.number_of(pull.url || pull.number)
      end
    end
  end
end
