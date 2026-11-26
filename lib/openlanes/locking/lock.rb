# frozen_string_literal: true

module OpenLanes
  module Locking
    # One active lock, as the register reports it.
    #
    # @!attribute [r] agent
    #   @return [String] the holder's agent id
    # @!attribute [r] scope
    #   @return [String] relative to {#tree}, e.g. `.plans/003.00━━🟡━━❯x/**`
    # @!attribute [r] tree
    #   @return [String] the checkout the lock was taken in
    # @!attribute [r] intent
    #   @return [String, nil]
    Lock = Data.define(:agent, :scope, :tree, :intent) do
      # @return [String] the scope's literal part: `**` is "", `a/b/**` is "a/b"
      def fixed = scope.split("/").take_while { !it.match?(/[*?\[{]/) }.join("/")

      # @return [String] who holds it and why, for the log
      def to_s = "#{agent} (#{intent || "no intent given"})"
    end
  end
end
