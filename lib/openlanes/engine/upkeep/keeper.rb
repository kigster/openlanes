# frozen_string_literal: true

module OpenLanes
  module Engine
    module Upkeep
      # The one face the dispatcher sees: each method hands off to the
      # collaborator that owns the duty, so the dispatcher depends on none of
      # them.
      class Keeper
        # @param addressing [Addressing]
        # @param sweep [Sweep]
        # @param resolution [Resolution]
        # @param owed [Owed]
        def initialize(addressing:, sweep:, resolution:, owed:)
          @addressing = addressing
          @sweep = sweep
          @resolution = resolution
          @owed = owed
        end

        # @return [Array<String>] see {Addressing#call}
        def address = @addressing.call

        # @param subjects [Array<Plans::Subject>]
        # @param busy [Array<String>]
        # @return [Sweep::Result]
        def sweep(subjects, busy: []) = @sweep.call(subjects, busy:)

        # A conflict that could not be started now is asked about again on
        # the next sweep.
        #
        # @param conflict [Conflict]
        # @return [void]
        def later(conflict) = @owed.recheck(conflict)

        # @return [Report] see {Resolution#rebased}
        def rebased(conflict, checkout, outcome) = @resolution.rebased(conflict, checkout, outcome)

        # @return [Report] see {Resolution#finished}
        def finished(conflict, checkout, result, held:) = @resolution.finished(conflict, checkout, result, held:)
      end
    end
  end
end
