# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # When this refactor took the global lock (R6), which {GlobalLock}
      # counts its expiry from. Kept here because the folder's name says ⭐
      # but not since when. Not {Plans::GlobalLock}, which reads these back.
      class LockRecord < Section
        # @return [Time, nil]
        def global_lock_taken_at
          text = read.dig("global_lock", "taken_at") or return nil
          parse_time(text)
        end

        # A second call keeps the first time, so a restarted engine does not
        # hand the refactor a fresh lock.
        #
        # @param at [Time]
        # @return [Time] the time kept
        def take_global_lock!(at)
          kept = global_lock_taken_at and return kept

          update { |data| data["global_lock"] = { "taken_at" => at.utc.iso8601 } }
          at
        end

        # Forget the lock. Writes nothing when there was none.
        #
        # @return [void]
        def release_global_lock!
          return unless read.key?("global_lock")

          update { |data| data.delete("global_lock") }
        end
      end
    end
  end
end
