# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # What the session of an agent's last round already holds of its
      # journal ({Journal::Held}), kept beside its rounds under {PlanState::HELD}.
      class Holds < JournalSection
        # @param agent [String]
        # @return [OpenLanes::Plans::Journal::Held, nil]
        def held(agent)
          record = read.dig(MEMORY, agent, HELD)
          record && Journal::Held.new(session: record["session"].to_s, through: record["through"].to_i)
        end

        # Record that +session+ holds every entry written so far, counted
        # under the write's lock, so an entry added a moment later is sent
        # again next round rather than lost.
        #
        # @param agent [String]
        # @param session [String]
        # @return [OpenLanes::Plans::Journal::Held]
        def hold!(agent, session)
          through = nil
          update do |data|
            through = entries_in(rounds_for(data, agent))
            memory_of(data, agent)[HELD] = { "session" => session, "through" => through }
          end
          Journal::Held.new(session:, through:)
        end

        # Drop the agent's hold, so its next prompt carries the whole
        # journal. Writes nothing when there is none.
        #
        # @param agent [String]
        # @return [void]
        def forget_held!(agent)
          return unless held(agent)

          update { |data| data.dig(MEMORY, agent)&.delete(HELD) }
          nil
        end
      end
    end
  end
end
