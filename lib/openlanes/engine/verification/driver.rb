# frozen_string_literal: true

module OpenLanes
  module Engine
    module Verification
      # Everything the dispatcher asks about verification, in one object, so
      # the loop gains a few calls rather than a second job: the hand-off
      # from hansolo, the app around chewie's run, the verdict, and the CI
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
        def initialize(outcome:, worktree:, app: nil, supervisor_factory: Apps.method(:supervisor),
          clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, interval: INTERVAL)
          @outcome = outcome
          @worktree = worktree
          @app = app
          @factory = supervisor_factory
          @clock = clock
          @interval = interval
          @last = nil
          @thread = nil
          @ready = Set.new
        end

        # @return [Outcome]
        attr_reader :outcome

        # hansolo approved: on to 🧪, when the pull request carries a verdict
        # that goes on to verification ({Verification::FROM_REVIEW}) and is
        # built from the branch chewie would be run in. The checkout's branch
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
          unless Verification.from_review?(labels)
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
          Verification.round_for(subject.feature.path).make!
          subject.machine.promote!(:verifying)
          "on to 🧪 verification"
        rescue OpenLanes::Error => e
          "stays 👀: #{e.message}"
        end

        # The app up around chewie's run, and chewie told where it is.
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
        # A verified round counts only once the engine pushed its evidence
        # ({Round#published?}); one chewie reported but the engine never
        # published goes back to chewie, in a new round.
        #
        # @return [Boolean] whether the plan waits on CI rather than on chewie
        def awaiting_ci?(subject)
          return false unless subject.status.key == :verifying

          round = Round.latest(subject.feature.path)
          !round.nil? && round.published? && round.report&.verdict == :verified
        end

        # Look at CI for every plan waiting on it, on a thread of its own:
        # the coverage gate runs the project's whole suite, and the tick may
        # not wait for that. What the previous look found is handed back on
        # the first call after it finished.
        #
        # @param subjects [Array<OpenLanes::Plans::Subject>] plans the loop may touch
        # @return [Array<Settled>] finished looks, often none
        def poll(subjects)
          if @thread && !@thread.alive?
            done = @thread.value || []
            @thread = nil
            @ready.merge(done.select { it.result.kind == :ready }.map { [it.plan, it.round] })
            return done
          end
          return [] if @thread || !due?

          waiting = subjects.select { awaiting_ci?(it) && !@ready.include?(ready_key(it)) }
          @thread = Thread.new { waiting.filter_map { settle(it) } } unless waiting.empty?
          []
        end

        # @return [void] waits for a look under way, so a run that is ending
        #   does not leave a coverage run behind it
        def join = @thread&.join

        private

        # @return [Settled, nil]
        def settle(subject)
          pull = open_pull(subject) or return nil
          checkout = @worktree.checkout_for(subject.feature)
          round = Round.latest(subject.feature.path)
          result = @outcome.settle(checkout:, plan: subject, pull:, round:)
          Settled.new(plan: subject.feature.ordinal.to_s, result:, round: round&.number)
        # StandardError, not only OpenLanes::Error: one plan's surprise from
        # `gh` must not end the look for the others, nor the run.
        rescue StandardError => e
          UI.log("verification not settled: #{e.message.lines.first.to_s.strip}", level: :warn, plan: subject.feature.ordinal.to_s)
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
