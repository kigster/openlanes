# frozen_string_literal: true

module OpenLanes
  module Plans
    # Writes down when a refactor took the global lock, and forgets it once
    # the refactor stops asking (R6). {GlobalLock} only reads, because asking
    # whether a plan may start must never change anything on disk; the
    # dispatcher calls this once per tick, after it has asked.
    class LockClock
      # @param state_for [#call] folder path => {PlanState}
      def initialize(state_for: PlanState.method(:for))
        @state_for = state_for
      end

      # Stamp the holder if it has no time yet, and clear the time of every
      # refactor that is no longer a claimant (finished, or parked before its
      # build began), so one that comes back starts a fresh clock. A lapsed
      # claimant keeps its time: clearing it would hand it a new lock.
      #
      # @param lock [OpenLanes::Plans::GlobalLock]
      # @param now [Time]
      # @return [void]
      def call(lock, now: Time.now)
        holder = lock.holder
        state(lock.subject(holder)).take_global_lock!(at: now) if holder && lock.taken_at(holder).nil?

        lock.refactors.each do |subject|
          next if lock.claimants.include?(subject.feature.ordinal.to_s)

          plan = state(subject)
          plan.release_global_lock! if plan.exist?
        end
      end

      private

      # @param subject [OpenLanes::Plans::Subject]
      # @return [OpenLanes::Plans::PlanState]
      def state(subject) = @state_for.call(subject.feature.path)
    end
  end
end
