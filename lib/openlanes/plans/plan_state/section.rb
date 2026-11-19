# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # What every {PlanState} section is built with: the {Document} and
      # nothing else, so a section never reaches into another one.
      class Section
        # @param document [OpenLanes::Plans::PlanState::Document]
        def initialize(document)
          @document = document
        end

        private

        # @return [OpenLanes::Plans::PlanState::Document]
        attr_reader :document

        # @return [Hash]
        def read = document.read

        # @yieldparam data [Hash]
        # @return [Hash]
        def update(&) = document.update(&)

        # @param data [Hash]
        # @param agent [String]
        # @return [Hash] the agent's journal rounds under {PlanState::MEMORY}, created when missing
        def rounds_for(data, agent) = ((data[MEMORY] ||= {})[agent] ||= {})["rounds"] ||= {}

        # @param rounds [Hash] journal rounds
        # @return [Integer] how many entries they hold between them
        def entries_in(rounds) = rounds.sum { |_, value| Array(value["entries"]).size }

        # @param text [String, nil]
        # @return [Time]
        def parse_time(text) = Document.parse_time(text)
      end
    end
  end
end
