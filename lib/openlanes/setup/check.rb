# frozen_string_literal: true

module OpenLanes
  module Setup
    # One question asked of the machine, and its answer.
    #
    # @!attribute name   [String] what was checked, as the report labels it
    # @!attribute ok     [Boolean]
    # @!attribute detail [String] what was found
    # @!attribute fix    [String, nil] the command that turns a ✗ into a ✓
    Check = Data.define(:name, :ok, :detail, :fix) do
      # @return [Boolean]
      def ok? = ok == true
    end
  end
end
