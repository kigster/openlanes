# frozen_string_literal: true

module OpenLanes
  module Execution
    module Throttle
      # One "not now" from a provider.
      #
      # @!attribute [r] kind
      #   @return [Symbol] :rate_limit or :overloaded
      # @!attribute [r] retry_after
      #   @return [Float, nil] seconds the provider asked for, when it said
      # @!attribute [r] detail
      #   @return [String] the line that gave it away, for the log
      Limit = Data.define(:kind, :retry_after, :detail) do
        # @return [String] "rate limited" or "overloaded", as a person reads it
        def to_s = kind == :overloaded ? "provider overloaded" : "rate limited"
      end
    end
  end
end
