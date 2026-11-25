# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # The base of the three sections that touch an agent's journal (M2):
      # {Memory}, {Holds} and {Answers}. It owns where a journal lives,
      # `memory/<agent>/rounds` under {PlanState::MEMORY}, so a change to that
      # layout is made here once. On {Section} the twelve sections that never
      # see a journal inherited these helpers, and the layout was spelled out
      # again in each of the three.
      class JournalSection < Section
        private

        # @param agent [String]
        # @return [void]
        # @raise [OpenLanes::Error] on an agent name that is not one token
        def journal_agent!(agent)
          raise Error, "a journal needs an agent name" unless agent.to_s.match?(/\A[\w-]+\z/)
        end

        # @param data [Hash]
        # @param agent [String]
        # @return [Hash] the agent's record under {PlanState::MEMORY}, created when missing
        def memory_of(data, agent) = (data[MEMORY] ||= {})[agent] ||= {}

        # @param data [Hash]
        # @param agent [String]
        # @return [Hash] the agent's journal rounds, created when missing
        def rounds_for(data, agent) = memory_of(data, agent)["rounds"] ||= {}

        # @param data [Hash]
        # @param agent [String]
        # @return [Hash] the agent's journal rounds as read; empty, and not
        #   added to +data+, when there are none
        def rounds_in(data, agent) = data.dig(MEMORY, agent, "rounds") || {}

        # @param rounds [Hash] journal rounds
        # @return [Integer] how many entries they hold between them
        def entries_in(rounds) = rounds.sum { |_, value| Array(value["entries"]).size }
      end
    end
  end
end
