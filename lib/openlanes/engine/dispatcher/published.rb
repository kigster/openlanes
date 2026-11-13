# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What publishing did for one Completed build: the attempt with the
      # pull request noted, the plan read again so the row the publisher
      # recorded is in it, and whether the publisher refused.
      #
      # @!attribute [r] attempt
      #   @return [OpenLanes::Engine::Runner::Attempt]
      # @!attribute [r] subject
      #   @return [OpenLanes::Plans::Subject]
      # @!attribute [r] refused
      #   @return [Boolean]
      Published = Data.define(:attempt, :subject, :refused, :untestable) do
        def initialize(untestable: false, **rest) = super
      end
    end
  end
end
