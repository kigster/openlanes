# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # One ledger line as {PlanState#sign!} receives it, checked before it is
      # written. Every field is required: the defaults live on the facade.
      Signature = Data.define(:agent, :round, :status, :note, :next_agent, :at) do
        # @return [void]
        # @raise [OpenLanes::Error] for a status outside the ledger's vocabulary,
        #   a handoff after anything but Completed, or an agent that is not one token
        def check!
          raise Error, "status must be one of #{Ledger::STATUSES.join(", ")}" unless Ledger::STATUSES.include?(status)
          raise Error, "only a Completed signature may name who is next" if next_agent && status != "Completed"
          raise Error, "a signature needs an agent name" unless agent.to_s.match?(/\A[\w-]+\z/)
        end

        # @return [Hash] in the key order `state.json` has always carried
        def to_json_h
          { "at" => at.iso8601, "agent" => agent, "status" => status, "round" => Integer(round),
            "note" => Ledger.words(note), "next" => next_agent }.compact
        end
      end
    end
  end
end
