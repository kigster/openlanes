# frozen_string_literal: true

module OpenLanes
  module Locking
    # What one `acquire` or `release` came to.
    #
    # @!attribute [r] status
    #   @return [Symbol] `:done`, `:refused` (somebody else holds it, or there
    #     was nothing to release) or `:failed` (the register could not answer)
    # @!attribute [r] message
    #   @return [String] the register's first line, for the log
    Outcome = Data.define(:status, :message) do
      def initialize(status:, message: "") = super

      # @return [Boolean]
      def done? = status == :done

      # @return [Boolean]
      def failed? = status == :failed
    end
  end
end
