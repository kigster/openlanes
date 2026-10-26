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
        # `review-ok-not-perfect` one goes back to 🔴 under `high` and `standard` (R4), and
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
        # round, still the same open pull request. One that changed is left
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

        # What R4 does with a `review-ok-not-perfect` pull request, short of
        # verifying it.
        #
        # @return [String, nil] what happened; nil when the quality lets it
        #   go on, or the verdict is not the one the quality decides
        def quality_says(subject, pull, labels)
          now = quality
          return nil unless Verification.ok_not_perfect?(labels) && now != :mvp

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

        # One plan's look, as it stood when the look began.
        Pending = Data.define(:plan, :subject, :round, :pull, :checkout)

        # @return [Pending, nil]
        def pending_for(subject)
          pull = open_pull(subject) or return nil

          Pending.new(plan: subject.feature.ordinal.to_s,
            subject:,
            round: Round.latest(subject.feature.path),
            pull:,
            checkout: @worktree.checkout_for(subject.feature))
        rescue StandardError => e
          not_settled(subject.feature.ordinal.to_s, e)
        end

        # On the look's thread: reads only.
        #
        # @return [Array(Pending, Outcome::Look), nil]
        def look_at(pending)
          [pending, @outcome.look(checkout: pending.checkout, plan: pending.subject, pull: pending.pull, round: pending.round)]
        # StandardError, not only OpenLanes::Error: one plan's surprise from
        # `gh` must not end the look for the others, nor the run.
        rescue StandardError => e
          not_settled(pending.plan, e)
        end

        # On the dispatcher's thread.
        #
        # @return [Settled, nil]
        def apply(pending, seen, subjects)
          subject = subjects.find { it.feature.ordinal.to_s == pending.plan } or return nil
          return nil unless still?(pending, subject)

          result = @outcome.settle(checkout: pending.checkout, plan: subject, pull: open_pull(subject), round: pending.round, seen:)
          @ready << [pending.plan, pending.round.number] if result.kind == :ready
          Settled.new(plan: pending.plan, result:, round: pending.round.number)
        rescue StandardError => e
          not_settled(pending.plan, e)
        end

        # @return [Boolean] whether the plan is as the look found it
        def still?(pending, subject)
          pull = open_pull(subject)
          awaiting_ci?(subject) && Round.latest(subject.feature.path)&.number == pending.round.number &&
            !pull.nil? && [pull.number, pull.url] == [pending.pull.number, pending.pull.url]
        end

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

        # @return [OpenLanes::Plans::PullRequest, nil]
        def open_pull(subject) = subject.pull_requests.select(&:open?).last

        # @return [Round]
        def latest(subject) = Round.latest(subject.feature.path) || Round.next(subject.feature.path)

        # @return [OpenLanes::Vcs::Worktree::Checkout]
        def checkout_of(task, subject) = task.checkout || @worktree.checkout_for(subject.feature)
      end
    end
  end
end
