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
        Result = Data.define(:kind, :note, :to) do
          def initialize(to: nil, **rest) = super
        end

        # Who the comment and the harness's own signature are from.
        AGENT = "chewie-verifier"

        # A signature that counts as a rejection: its note starts with the
        # word, as `rejected`, `rejected 1/2` (hansolo) or `rejected: …` (the
        # harness signing for chewie). Anchored rather than searched for: an
        # approving note that says "nothing to reject" is not a rejection, and
        # counting it would reach the arbitrator a round early.
        REJECTION = %r{\Arejected(?=\z|[\s:/])}i

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
        # @param max_rejections [Integer] see {Config#max_rejections}
        # @param arbitration [#call] given `plan:, count:, max:` at the cap
        # @param screenshots [#call] a round's folder to a {Screenshots}
        # @param clock [#call] the time now, for {NO_CHECKS_GRACE}
        def initialize(root:, publisher:, github:, outcomes:, agents:, review: Vcs::Review.new(github:),
          coverage_gate: CoverageGate.new, max_rejections: Config::DEFAULT_MAX_REJECTIONS,
          arbitration: Arbitration.new, screenshots: ->(dir) { Screenshots.new(dir:) }, clock: -> { Time.now })
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
        # checkout (a stray file, a push that would not go).
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
          Result.new(kind: :committed, note: "verified PR ##{number_of(pull)}; #{pushed}; waiting on CI")
        end

        # One look at a verified pull request, asked again until it is
        # labelled or rejected: CI pending waits, and so do no checks at all
        # within {NO_CHECKS_GRACE} of the verification; CI red or the
        # coverage gate withholding rejects; otherwise `ready-to-merge` goes on.
        #
        # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
        # @param plan [OpenLanes::Plans::Subject]
        # @param pull [OpenLanes::Plans::PullRequest] the plan's open pull request
        # @param round [Round] the verified round
        # @return [Result]
        def settle(checkout:, plan:, pull:, round:)
          number = number_of(pull)
          repo = Vcs::GitHub.repo_of(pull.url)
          return ready(number, "already #{Plans::ReviewLabel::READY_TO_MERGE}") if labelled_ready?(number, repo)

          ci = Vcs::CiGate.verdict(@github.checks(number:, repo:))
          return Result.new(kind: :waiting, note: "🧪 no checks yet on PR ##{number}; waiting for CI to start") if ci == :none && registering?(round)

          case ci
          when :pending then Result.new(kind: :waiting, note: "🧪 waiting on CI for PR ##{number}")
          when :red then reject(checkout:, plan:, pull:, round:, why: "CI is red on PR ##{number} after verification.")
          else gated(checkout:, plan:, pull:, round:)
          end
        end

        # @param pull [OpenLanes::Plans::PullRequest]
        # @return [Array<String>] the pull request's labels, as GitHub has them now
        # @raise [OpenLanes::Error] when GitHub cannot be asked
        def labels(pull) = @github.labels(number: number_of(pull), repo: Vcs::GitHub.repo_of(pull.url))

        # Every rejection of this plan so far, hansolo's and chewie's
        # together (M6). Derived from their signatures every time, never
        # stored: a count kept beside the ledger is a second answer to one
        # question.
        #
        # @param plan [OpenLanes::Plans::Subject]
        # @return [Integer]
        def rejections(plan)
          judges = @agents.all.select { %w[review verification].include?(it.phase.to_s) }
          files = judges.flat_map(&:ledger).uniq
          names = judges.map(&:name)
          Plans::Ledger.read(plan.feature.path, files).entries
                       .select { names.include?(it.agent) && it.completed? && it.note.to_s.strip.match?(REJECTION) }
                       .uniq { [it.agent, it.note, it.at.to_i / 60] }
                       .size
        end

        private

        # @return [Result]
        def gated(checkout:, plan:, pull:, round:)
          verdict = gate_verdict(checkout, plan, round)
          return reject(checkout:, plan:, pull:, round:, why: SETUP, counted: false) if verdict.unconfigured?
          return reject(checkout:, plan:, pull:, round:, why: withheld(verdict)) if verdict.withheld?

          result = @review.call(pr: pull.url || number_of(pull), label: Plans::ReviewLabel::READY_TO_MERGE)
          return Result.new(kind: :waiting, note: "🧪 #{Plans::ReviewLabel::READY_TO_MERGE} refused: #{result.reason}") if result.refused?

          # Plan 033 merges here in agent mode (R5): `ready-to-merge`, green
          # CI on the PR and on main, and a clean merge. Until then nothing
          # merges, and in human mode nothing ever does (M4).
          ready(number_of(pull), "#{Plans::ReviewLabel::READY_TO_MERGE}: #{verdict.reason}")
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
        # have registered on it yet. Timed from the round's report, which
        # chewie writes moments before {#pass} commits; read from disk rather
        # than remembered, so a restarted engine keeps the same window.
        #
        # @return [Boolean]
        def registering?(round)
          path = round&.report_path
          return false unless path && File.exist?(path)

          @clock.call - File.mtime(path) < NO_CHECKS_GRACE
        end

        # @return [Result]
        def ready(number, why) = Result.new(kind: :ready, note: "PR ##{number} #{why}; waiting for it to merge")

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
        #   never reached the branch, its note saying so first
        def uncommitted(checkout:, plan:, pull:, round:, failure:)
          why = "Verified, but #{Screenshots::FINAL} was not committed, so the pull request carries no evidence: #{failure}"
          result = reject(checkout:, plan:, pull:, round:, why:, counted: false)
          result.with(note: "verified PR ##{number_of(pull)} but NOT committed (#{failure}); #{result.note}")
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
          tally = counted ? "rejected #{count} of #{@max}" : "sent back for setup, not counted (#{count} of #{@max})"
          @arbitration.call(plan:, count:, max: @max) if counted && count >= @max
          moved = @outcomes.apply(PrWatch::Outcome.new(plan: plan.feature.ordinal.to_s,
            pr: number_of(pull),
            kind: :rejected,
            comments: [{ author: AGENT, url: pull.url.to_s, body: }]))
          label = labelled.refused? ? "#{Plans::ReviewLabel::REJECTED} refused: #{labelled.reason}" : Plans::ReviewLabel::REJECTED.name
          Result.new(kind: :rejected,
            note: "verification #{counted ? "rejected" : "sent back"} PR ##{number_of(pull)}, #{tally}; #{label}" \
                  "#{"; #{moved.note}" if moved}",
            to: moved&.to)
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
