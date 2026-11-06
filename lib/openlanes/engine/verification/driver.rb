# frozen_string_literal: true

module OpenLanes
  module Engine
    module Verification
      # Everything the dispatcher asks about verification, in one object, so
      # the loop gains a few calls rather than a second job: the hand-off
      # from staff-reviewer, the app around verifier's run, the verdict, and the CI
      # wait after a pass.
      #
      # The wait is read from disk, not remembered: a 🧪 plan whose newest
      # round says `verified` is waiting on CI. A run that ends while it
      # waits leaves nothing behind to clean up, and the next run, or a
      # staying one, picks the wait up where it stood.
      class Driver
        # One plan's wait, settled.
        #
        # @!attribute [r] plan
        #   @return [String] the ordinal
        # @!attribute [r] result
        #   @return [Outcome::Result]
        # @!attribute [r] round
        #   @return [Integer, nil] the round it settled
        Settled = Data.define(:plan, :result, :round) do
          def initialize(round: nil, **rest) = super
        end

        # Seconds between looks at CI, as {PrWatch} paces its own.
        INTERVAL = 15

        # @param outcome [Outcome]
        # @param worktree [OpenLanes::Vcs::Worktree] where a waiting plan's checkout is
        # @param app [OpenLanes::Apps::Definition, nil] the project's `app:`
        # @param supervisor_factory [#call] see {AppSession#initialize}
        # @param clock [#call] monotonic seconds
        # @param interval [Numeric] seconds between looks at CI
        # @param quality [Symbol, nil, #call] {Config#desired_codebase_quality},
        #   nil while the project is still to be asked (R4); a callable is
        #   asked each time, so an answer given mid-run counts at once
        def initialize(outcome:, worktree:, app: nil, supervisor_factory: Apps.method(:supervisor),
          clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, interval: INTERVAL, quality: nil)
          @outcome = outcome
          @quality = quality
          @worktree = worktree
          @app = app
          @factory = supervisor_factory
          @clock = clock
          @interval = interval
          @last = nil
          @thread = nil
          @ready = Set.new
          @looking = []
        end

        # @return [Outcome]
        attr_reader :outcome

        # staff-reviewer approved: on to 🧪, when the pull request carries a verdict
        # that goes on to verification ({Verification.from_review?}) and is
        # built from the branch verifier would be run in. A
        # `review-passed` one goes back to 🔴 under `high` and `standard` (R4), and
        # stays 👀 while the project has not said which quality it wants. The checkout's branch
        # is derived from the plan, and an adopted pull request may be built
        # from any other; verifying it there would test the wrong code.
        #
        # @param subject [OpenLanes::Plans::Subject] read fresh
        # @return [String, nil] what happened, for the attempt; nil when the
        #   folder cannot be 🧪 at all, and the plan finishes at 👀 as before
        def hand_off(subject)
          return nil unless subject.machine.may?(:verifying)

          pull = open_pull(subject) or return nil
          labels = @outcome.labels(pull)
          sent = quality_says(subject, pull, labels)
          return sent if sent

          unless Verification.from_review?(labels, quality:)
            verdict = (labels & Plans::ReviewLabel.names).join(", ")
            return "stays 👀: PR ##{pull.number.to_s.delete("#")} is labelled #{verdict.empty? ? "nothing" : verdict}, " \
                   "and only #{FROM_REVIEW.map(&:name).join(", ")} goes on to verification"
          end

          mismatch = @outcome.mismatch(checkout: @worktree.checkout_for(subject.feature), pull:)
          return "stays 👀: #{mismatch}; verify it by hand" if mismatch

          # A round of its own for this hand-off, before the rename carries
          # it into 🧪: the newest round otherwise may be one verified before
          # a rejection and a rebuild, and would be taken for this one,
          # waiting on CI, with the fixes never verified.
          round = Verification.round_for(subject.feature.path).make!
          skipped = skip(round, pull, labels)
          subject.machine.promote!(:verifying)
          skipped || "on to 🧪 verification"
        rescue OpenLanes::Error => e
          "stays 👀: #{e.message}"
        end

        # The app up around verifier's run, and verifier told where it is.
        #
        # @param task [OpenLanes::Engine::Runner::Task]
        # @param subject [OpenLanes::Plans::Subject]
        # @yieldreturn [Object] what the executor returned
        # @return [Object, AppSession::Failed]
        def around(task, subject)
          round = Verification.round_for(subject.feature.path).make!
          session = AppSession.new(definition: @app,
            root: task.root,
            plan: subject.feature.ordinal.to_s,
            branch: task.checkout&.branch.to_s,
            supervisor_factory: @factory)
          session.around do |statuses|
            File.write(File.join(round.dir, Round::APP_NOTE), AppSession.note(statuses, @app))
            yield
          end
        end

        # @param task [OpenLanes::Engine::Runner::Task]
        # @param subject [OpenLanes::Plans::Subject] read fresh
        # @param why [String, nil] see {Outcome#reject}
        # @return [Outcome::Result, nil] nil when the plan has no open pull request to reject
        def reject(task, subject, why: nil)
          pull = open_pull(subject) or return nil

          @outcome.reject(checkout: checkout_of(task, subject), plan: subject, pull:, round: latest(subject), why:)
        end

        # @param task [OpenLanes::Engine::Runner::Task]
        # @param subject [OpenLanes::Plans::Subject] read fresh
        # @return [Outcome::Result, nil] nil when the plan has no open pull request
        def pass(task, subject)
          pull = open_pull(subject) or return nil

          round = latest(subject)
          result = @outcome.pass(checkout: checkout_of(task, subject), plan: subject, pull:, round:)
          # Only now is the round waiting on CI ({#awaiting_ci?}).
          round.publish!(result.sha) if result.kind == :committed
          result
        end

        # @param subject [OpenLanes::Plans::Subject]
        # A verified or skipped round counts only once the engine pushed its
        # evidence ({Round#published?}); one verifier reported but the engine
        # never published goes back to verifier, in a new round. Skipped is the
        # mvp path ({#skip}): verifier never ran, but CI and the coverage gate
        # still stand. A skip written under `mvp` is not a wait once the
        # project has switched to `high` or `standard`: verifier must run.
        #
        # @return [Boolean] whether the plan waits on CI rather than on verifier
        def awaiting_ci?(subject)
          return false unless subject.status.key == :verifying

          round = Round.latest(subject.feature.path)
          return false unless round&.published?

          case round.report&.verdict
          when :verified then true
          when :skipped then quality == :mvp
          else false
          end
        end

        # Look at CI for every plan waiting on it, on a thread of its own:
        # the coverage gate runs the project's whole suite, and the tick may
        # not wait for that. The thread only reads ({Outcome#look}). What it
        # found is acted on here, on the dispatcher's thread, on the first
        # call after it finished: labelling, rejecting, mailing and renaming
        # are lifecycle changes, and doing them on the thread raced the PR
        # watcher and the builders over the same folder.
        #
        # Each plan is checked again before its look is acted on, since the
        # look may have taken minutes: still 🧪, still waiting on the same
        # round, still the same open pull requests. One that changed is left
        # for the next look.
        #
        # @param subjects [Array<OpenLanes::Plans::Subject>] plans the loop
        #   may touch, read fresh, the ones being looked at included
        # @return [Array<Settled>] finished looks, often none
        def poll(subjects)
          if @thread && !@thread.alive?
            looked = @thread.value || []
            @thread = nil
            @looking = []
            return looked.filter_map { |pending, seen| apply(pending, seen, subjects) }
          end
          return [] if @thread || !due?

          waiting = subjects.select { awaiting_ci?(it) && !@ready.include?(ready_key(it)) }.filter_map { pending_for(it) }
          return [] if waiting.empty?

          @looking = waiting.map(&:plan)
          @thread = Thread.new { waiting.filter_map { look_at(it) } }
          []
        end

        # @return [Boolean] whether a look is under way, or finished and not
        #   yet acted on: a run may not end before {#poll} has had it
        def busy? = !@thread.nil?

        # @return [Array<String>] ordinals being looked at: no agent may start
        #   on them and no rename may touch them until the look is acted on
        def looking = @looking.dup

        # @return [void] waits for a look under way
        def join = @thread&.join

        private

        # What R4 does with a `review-passed` pull request, short of
        # verifying it.
        #
        # @return [String, nil] what happened; nil when the quality lets it
        #   go on, or the verdict is not the one the quality decides
        def quality_says(subject, pull, labels)
          now = quality
          return nil unless Verification.passed?(labels) && now != :mvp

          number = pull.number.to_s.delete("#")
          return unasked(subject, number) if now.nil?

          to = Outcome::SEND_BACK.fetch(now, :rejected)
          return nil unless subject.machine.may?(to)

          # Counted, as any rejection is, so a PR labelled the same round
          # after round reaches `merge.max_rejections` and the arbitrator.
          result = @outcome.send_back_for_quality(plan: subject, pull:, quality: now)
          "back to #{Plans::STATUS_BY_KEY.fetch(to).emoji}: #{result.note}; #{Agents::Names::BACKEND_CODER} and #{Agents::Names::FRONTEND_CODER} answer every comment that is not ✅"
        end

        # An approved pull request under `mvp` (plan 035): the round is
        # written skipped and published here, in verifier's place, so the
        # plan waits on CI and the coverage gate ({#awaiting_ci?}) and
        # verifier is never started on it. The verdict is `skipped`, not
        # `verified`: a later reader of report.md must not take this for
        # verifier having run.
        #
        # @param round [Round] made for this hand-off
        # @return [String, nil] what happened; nil when verifier verifies it
        def skip(round, pull, labels)
          now = quality
          return nil unless Verification.skips_verification?(labels, quality: now)

          why = "PR ##{pull.number.to_s.delete("#")} is #{Plans::ReviewLabel::APPROVED.name} and " \
                "desired_codebase_quality is #{now}"
          File.write(round.report_path,
            "# Verification, round #{round.number}\n\nVerdict: skipped (#{now})\n\nSkipped: #{why}.\n")
          round.publish!("skipped")
          "on to 🧪, verification skipped: #{why}; waiting on CI"
        end

        # @return [Symbol, nil]
        def quality = @quality.respond_to?(:call) ? @quality.call : @quality

        # The key is missing: R4's question goes to a person, once per
        # project, and the plan waits on it at 👀.
        #
        # @return [String]
        def unasked(subject, number)
          asked = QualityQuestion.ask!(subject.feature.path) ? "asked in the drawer" : "already asked on another plan"
          "stays 👀: PR ##{number} is labelled #{Verification::ON_QUALITY.name}, " \
            "and desired_codebase_quality is not set in #{Config::FILE}; say #{Config::QUALITIES.join(", ")} (#{asked})"
        end

        # One plan's look, as it stood when the look began. Every open pull
        # request of the plan, not only its own: 🧪 → 🏁 asks that each carry
        # `ready-to-merge` ({Outcome#ready}), and looking at the last alone
        # left a sibling (adopted, or opened by a person) unlabelled, with
        # the plan waiting at 🧪 for ever (issue #170).
        #
        # @!attribute [r] pulls
        #   @return [Array<OpenLanes::Plans::PullRequest>] open, the plan's own last
        Pending = Data.define(:plan, :subject, :round, :pulls, :checkout)

        # @return [Pending, nil]
        def pending_for(subject)
          pulls = open_pulls(subject)
          return nil if pulls.empty?

          Pending.new(plan: subject.feature.ordinal.to_s,
            subject:,
            round: Round.latest(subject.feature.path),
            pulls:,
            checkout: @worktree.checkout_for(subject.feature))
        rescue StandardError => e
          not_settled(subject.feature.ordinal.to_s, e)
        end

        # On the look's thread: reads only. A sibling built from another
        # branch is not measured in the plan's checkout, which holds other
        # code ({Outcome#look}); the plan's own pull request always is, as
        # {#hand_off} already refused one built elsewhere.
        #
        # @return [Array(Pending, Array<Outcome::Look>), nil] one look per pull request
        def look_at(pending)
          own = pending.pulls.last
          looks = pending.pulls.map do |pull|
            measure = pull.equal?(own) || @outcome.mismatch(checkout: pending.checkout, pull:).nil?
            @outcome.look(checkout: pending.checkout, plan: pending.subject, pull:, round: pending.round, measure:)
          end
          [pending, looks]
        # StandardError, not only OpenLanes::Error: one plan's surprise from
        # `gh` must not end the look for the others, nor the run.
        rescue StandardError => e
          not_settled(pending.plan, e)
        end

        # On the dispatcher's thread. A failing look is acted on alone, so a
        # red sibling rejects the plan before any other pull request is
        # labelled `ready-to-merge`. Otherwise each is settled in turn, and
        # the last one labelled moves the plan to 🏁; the walk stops at the
        # first that moves it, since the rename leaves +subject+ stale.
        #
        # @return [Settled, nil]
        def apply(pending, seen, subjects)
          subject = subjects.find { it.feature.ordinal.to_s == pending.plan } or return nil
          return nil unless still?(pending, subject)

          pairs = pending.pulls.zip(seen)
          failing = pairs.find { |_, look| look.failing? }
          results = []
          (failing ? [failing] : pairs).each do |pull, look|
            results << @outcome.settle(checkout: pending.checkout, plan: subject, pull:, round: pending.round, seen: look)
            break if results.last.to || results.last.kind == :rejected
          end
          result = combined(results)
          @ready << [pending.plan, pending.round.number] if result.kind == :ready
          Settled.new(plan: pending.plan, result:, round: pending.round.number)
        rescue StandardError => e
          not_settled(pending.plan, e)
        end

        # One plan's results as one: the one that moved the folder or
        # rejected, when one did; otherwise waiting while any pull request
        # waits, and ready once all are. One pull request's result is
        # returned as it is.
        #
        # @param results [Array<Outcome::Result>]
        # @return [Outcome::Result]
        def combined(results)
          return results.first if results.one?

          decisive = results.find { it.to || it.kind == :rejected }
          kind = decisive&.kind || (results.all? { it.kind == :ready } ? :ready : :waiting)
          Outcome::Result.new(kind:, to: decisive&.to, note: results.map(&:note).join("; "))
        end

        # @return [Boolean] whether the plan is as the look found it: still
        #   waiting on the same round, with the same open pull requests
        def still?(pending, subject)
          awaiting_ci?(subject) && Round.latest(subject.feature.path)&.number == pending.round.number &&
            identities(open_pulls(subject)) == identities(pending.pulls)
        end

        # @return [Array<Array>] each pull request's number and URL
        def identities(pulls) = pulls.map { [it.number, it.url] }

        # @return [nil]
        def not_settled(plan, error)
          UI.log("verification not settled: #{error.message.lines.first.to_s.strip}", level: :warn, plan:)
          nil
        end

        # The first look comes at once; after that, one per interval.
        #
        # @return [Boolean]
        def due?
          now = @clock.call
          return false if @last && now - @last < @interval

          @last = now
          true
        end

        # Ready is remembered per round, not per plan: a plan rejected after
        # `ready-to-merge`, rebuilt and verified again is a new round, and
        # must be looked at again.
        #
        # @return [Array(String, Integer)]
        def ready_key(subject) = [subject.feature.ordinal.to_s, Round.latest(subject.feature.path)&.number]

        # @return [OpenLanes::Plans::PullRequest, nil] the plan's own: the last open one
        def open_pull(subject) = open_pulls(subject).last

        # @return [Array<OpenLanes::Plans::PullRequest>]
        def open_pulls(subject) = subject.pull_requests.select(&:open?)

        # @return [Round]
        def latest(subject) = Round.latest(subject.feature.path) || Round.next(subject.feature.path)

        # @return [OpenLanes::Vcs::Worktree::Checkout]
        def checkout_of(task, subject) = task.checkout || @worktree.checkout_for(subject.feature)
      end
    end
  end
end
