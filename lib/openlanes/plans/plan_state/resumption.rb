# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # What {PlanState#resumption} decided.
      #
      # @!attribute [r] session
      #   @return [String, nil] the id to resume, nil to start fresh
      # @!attribute [r] reason
      #   @return [String] why, for the log
      Resumption = Data.define(:session, :reason) do
        # @return [Boolean]
        def resume? = !session.nil?
      end
    end
  end
end
