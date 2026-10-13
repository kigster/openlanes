# frozen_string_literal: true

module OpenLanes
  module Evals
    # One check's answer.
    #
    # @!attribute [r] name
    #   @return [String] the check, as a reader would name it
    # @!attribute [r] ok
    #   @return [Boolean]
    # @!attribute [r] detail
    #   @return [String] what was found, pass or fail
    Verdict = Data.define(:name, :ok, :detail) do
      # @return [Boolean]
      def ok? = ok
    end
  end
end
