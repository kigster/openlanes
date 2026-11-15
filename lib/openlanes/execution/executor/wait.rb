# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # One wait out of a provider's rate limit or overload: the limit, the
      # waits it belongs to, and how long this one lasts (nil once the
      # waiting is given up).
      #
      # @!attribute [r] limit
      #   @return [OpenLanes::Execution::Throttle::Limit]
      # @!attribute [r] waits
      #   @return [OpenLanes::Execution::Throttle::Waits]
      # @!attribute [r] seconds
      #   @return [Float, nil]
      Wait = Data.define(:limit, :waits, :seconds)
    end
  end
end
