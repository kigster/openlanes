# frozen_string_literal: true

module OpenLanes
  module Memory
    # Who a lessons section is for, when that is a phase and not one of the
    # openlanes agents: an agent working outside a run (`openlanes memory list
    # --phase build`). It answers +name+ and +phase+ the way an
    # {Agents::Agent} does, so {Library#for} and {Section} take it unchanged
    # and there is one selector, not two that could disagree.
    #
    # It has no name, so a lesson addressed to one agent by name is not for
    # it: only lessons addressed to the phase or to `all`.
    #
    # @!attribute [r] phase
    #   @return [String]
    Audience = Data.define(:phase) do
      # @return [nil] no agent is named
      def name = nil
    end
  end
end
