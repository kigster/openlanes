# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # A person's answers to an agent's `blocked.md` questions (M3), and who
      # asked them.
      class Answers < JournalSection
        # Appended to the agent's latest round, once: the check is made under
        # the lock the write takes, so two drains at once cannot both write it.
        #
        # @param agent [String]
        # @param entry [OpenLanes::Plans::Journal::Entry] the question with its answer
        # @return [OpenLanes::Plans::Journal::Entry, nil] nil when it was there
        # @raise [OpenLanes::Error] on an agent name that is not one token
        def answer!(agent, entry)
          journal_agent!(agent)

          written = nil
          record = entry.to_json_h
          update do |data|
            rounds = rounds_for(data, agent)
            written = entry unless rounds.each_value.any? { Array(it["entries"]).include?(record) }
            latest(rounds)["entries"] << record if written
          end
          written
        end

        # Whoever blocked last, by a round that settled Blocked or a Blocked
        # signature; neither kind outranks the other.
        #
        # @return [String, nil] nil when nothing on record ever blocked
        def blocked_by
          data = read
          blocks = blocked(data["stages"]) { it["finished_at"] || it["started_at"] } + blocked(data["signatures"]) { it["at"] }
          blocks.each_with_index.max_by { |(at, _), i| [at, i] }&.first&.last
        end

        private

        # @return [Hash] the agent's latest journal round, the one that asked
        def latest(rounds) = rounds[(rounds.keys.map(&:to_i).max || 1).to_s] ||= { "entries" => [] }

        # @param records [Array<Hash>] stages or signatures
        # @yieldparam record [Hash]
        # @yieldreturn [String] when it blocked
        # @return [Array(Time, String)] each Blocked record's time and agent
        def blocked(records)
          records.select { it["status"] == "Blocked" }.map { [parse_time(yield(it)), it["agent"]] }
        end
      end
    end
  end
end
