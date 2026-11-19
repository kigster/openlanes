# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # Each agent's journal on this plan (M2): the lines it printed as it
      # worked, kept under {PlanState::MEMORY}, one record per journal round.
      class Memory < Section
        # The keys a journal round opens with, kept beside the code that
        # writes the round, not on the facade.
        #
        # @param round [Integer, nil] the harness round
        # @param state [#to_s, nil] the folder's state
        # @return [Hash]
        def self.opening(round, state) = { "round" => round, "state" => state&.to_s }.compact

        # One agent's journal, oldest round first, each entry numbered as the
        # agent refers to it: 1 up, across every round.
        #
        # @param agent [String]
        # @return [Array<OpenLanes::Plans::Journal::Round>]
        def journal(agent)
          rounds = read.dig(MEMORY, agent, "rounds") || {}
          first = 1
          rounds.sort_by { |key, _| key.to_i }.map do |key, value|
            entries = Array(value["entries"]).map { Journal::Entry.from_h(it) }
            round = Journal::Round.new(number: key.to_i, round: value["round"], state: value["state"], entries:, first:)
            first += entries.size
            round
          end
        end

        # Append entries to one journal round. With no +number+ the next one
        # is taken under the write's lock. An `override` must name an entry
        # before its own.
        #
        # @param agent [String]
        # @param entries [Array<OpenLanes::Plans::Journal::Entry>]
        # @param number [Integer, nil]
        # @param opening [Hash] from {.opening}, for a round started here
        # @return [Array(Integer, Array<OpenLanes::Plans::Journal::Rejection>)]
        # @raise [OpenLanes::Error] on an agent name that is not one token
        def journal!(agent, entries, number, opening)
          raise Error, "a journal needs an agent name" unless agent.to_s.match?(/\A[\w-]+\z/)

          rejected = []
          update do |data|
            rounds = rounds_for(data, agent)
            number ||= rounds.keys.map(&:to_i).max.to_i + 1
            target = (rounds[number.to_s] ||= opening.merge("entries" => []))
            append(target, entries, entries_in(rounds), rejected)
          end
          [number, rejected]
        end

        private

        # @return [void]
        def append(target, entries, count, rejected)
          entries.each do |entry|
            if entry.overrides && entry.overrides > count
              rejected << Journal::Rejection.new(line: Journal.line(entry.kind, entry.text, overrides: entry.overrides),
                reason: "entry #{count + 1} overrides #{entry.overrides}, which is not before it")
              next
            end
            target["entries"] << entry.to_json_h
            count += 1
          end
        end
      end
    end
  end
end
