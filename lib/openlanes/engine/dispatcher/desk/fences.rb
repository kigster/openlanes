# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # Plans no agent may be started on and no rename may touch, and the
        # reasons each one is fenced off.
        class Fences
          # @param desk [Desk] read for what is running, draining and held
          def initialize(desk)
            @desk = desk
          end

          # One being discarded or drained, one another machine holds (W26),
          # and one whose `locked-by.pid` another run wrote.
          #
          # @return [Array<String>]
          def untouchable
            busy + runner.tree.subjects.select { runner.foreign?(it) || locked_elsewhere?(it) || held_outside?(it) }
                         .map { it.feature.ordinal.to_s }
          end

          # Plans whose CI and coverage are being looked at off the loop's
          # thread. Untouchable until the look is acted on: a builder started
          # in the checkout the suite is running in, or a person's rejection
          # renaming the folder under it, would leave the look acting on a
          # plan that is no longer the one it read.
          #
          # @return [Array<String>]
          def verifying_now = runner.verification&.looking || []

          # Plans the arbitrator is being asked about off the loop's thread,
          # untouchable for the same reason until its ruling is applied.
          #
          # @return [Array<String>]
          def arbitrating_now = runner.arbitration&.asking || []

          # The Redis claim covers machines that share one; the lock file
          # covers a second run on this machine, or one that never reached
          # Redis. Without this check such a run renamed the folder at start,
          # wrote its own lock over the holder's, and deleted it when its
          # agent finished. This run's own lock is not a reason to stay out:
          # a pair shares it.
          #
          # @param subject [OpenLanes::Plans::Subject]
          # @return [Boolean]
          def locked_elsewhere?(subject) = Plans::Lock.read(subject.feature.path)&.held_elsewhere? || false

          # An agent outside openlanes holds the plan's folder or its worktree
          # in alock (W31). Said once per holder, not on every tick it stays held.
          #
          # @param subject [OpenLanes::Plans::Subject]
          # @return [Boolean]
          def held_outside?(subject)
            held = @desk.agent_locks&.held_elsewhere(subject.feature.path, checkout: runner.checkout_path(subject))
            ordinal = subject.feature.ordinal.to_s
            said = @desk.said_outside
            UI.log("held outside openlanes by #{held}; stepping around it", plan: ordinal) if held && said[ordinal] != held
            said[ordinal] = held
            !held.nil?
          end

          # Blocked plans in scope that this machine may answer for: on the
          # board whether or not an agent touched them this run, so their
          # questions reach the page from the moment the run starts.
          #
          # @return [Array<String>] ordinals
          def waiting = runner.blocked.reject { runner.foreign?(it) }.map { it.feature.ordinal.to_s }

          private

          def runner = @desk.runner

          def busy
            @desk.running.map { @desk.plan_of(it) } + @desk.discarding.keys + @desk.unblocking.map(&:ordinal) +
              verifying_now + arbitrating_now
          end
        end
      end
    end
  end
end
