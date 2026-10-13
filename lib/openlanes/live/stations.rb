# frozen_string_literal: true

module OpenLanes
  module Live
    # The stops on the page's board: the {Plans::StateMachine::SPINE}, with
    # the states a person does not need told apart folded into one stop.
    #
    # The grouping and the labels are the page's vocabulary and are written
    # here; which agents work at each stop is not, and comes from each
    # agent's `handles:`. A spec walks the spine to prove every state on it
    # has a stop, in spine order.
    module Stations
      # One stop.
      #
      # @!attribute [r] key
      #   @return [Symbol] a spine state's key, or :pr
      # @!attribute [r] label
      #   @return [String]
      # @!attribute [r] states
      #   @return [Array<Symbol>] the states a plan at this stop may be in
      # @!attribute [r] agents
      #   @return [Array<String>] agents whose `handles:` names one of {#states}
      Station = Data.define(:key, :label, :states, :agents) do
        # @return [Hash] `Station` in `types.ts`
        def wire = { key: key.to_s, label:, agents: }
      end

      # Key, label and the states folded into it, in spine order. ⭐️ Planned
      # sits with 🟡 Building and 🟢 Ready for Review with 👀 In Review,
      # because on the board each pair is one stop with the same agents.
      # 🔴 Rejected sits at Building too: luke and rey rework it there, and
      # placed by the spine alone it showed them at Building UI, a stop whose
      # agent list leaves luke out.
      GROUPS = [
        [:new, "New", %i[new]],
        [:researched, "Researched", %i[researched retroactive]],
        [:ready_for_planning, "Planning", %i[ready_for_planning]],
        [:building, "Building", %i[planned building rejected]],
        [:building_ui, "Building UI", %i[building_ui]],
        [:in_review, "Review", %i[ready_for_review in_review]],
        [:pr, "Pull request", %i[approved deployed]]
      ].freeze

      module_function

      # @param registry [OpenLanes::Agents::Registry]
      # @return [Array<Station>]
      def all(registry)
        GROUPS.map do |key, label, states|
          Station.new(key:, label:, states:, agents: registry.all.select { |a| a.handles.intersect?(states) }.map(&:name))
        end
      end

      # The stop a plan in +state+ is shown at. A state off the spine (🔴,
      # 💩, 😱) is shown where the spine takes it next; one with no way
      # forward (⭕️, 🅱️) where the plan was when it stopped, which only
      # its history knows.
      #
      # @param state [Symbol]
      # @param before [Symbol, nil] the state the plan was worked in last
      # @return [Symbol]
      def key_for(state, before: nil)
        [state, Plans::StateMachine::SPINE[state], before].each do |candidate|
          found = GROUPS.find { |_, _, states| states.include?(candidate) } and return found.first
        end
        GROUPS.first.first
      end
    end
  end
end
