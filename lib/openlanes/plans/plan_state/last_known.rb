# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # The resume records interrupted agents leave, keyed by agent under
      # {PlanState::LAST_KNOWN}, so an agent interrupted twice leaves one entry.
      class LastKnown < Section
        # A harness entry does not replace the agent's own of the same round
        # or later: see {LastKnownState#supersedes?}.
        #
        # @param agent [String]
        # @param entry [OpenLanes::Plans::LastKnownState]
        # @return [OpenLanes::Plans::LastKnownState] the entry kept
        # @raise [OpenLanes::Error] on an agent name that is not one token
        def record_last_known(agent, entry)
          raise Error, "a resume record needs an agent name" unless agent.to_s.match?(/\A[\w-]+\z/)

          kept = entry
          update do |data|
            section = (data[LAST_KNOWN] ||= {})
            existing = section[agent] && LastKnownState.from_h(section[agent])
            entry.supersedes?(existing) ? (section[agent] = entry.to_json_h) : (kept = existing)
          end
          kept
        end

        # @param agent [String]
        # @return [OpenLanes::Plans::LastKnownState, nil]
        def last_known(agent) = last_known_states[agent]

        # @return [Hash{String => OpenLanes::Plans::LastKnownState}]
        def last_known_states
          (read[LAST_KNOWN] || {}).transform_values { |h| LastKnownState.from_h(h) }
        end
      end
    end
  end
end
