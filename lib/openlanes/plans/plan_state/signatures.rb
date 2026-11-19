# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # The agents' ledger lines, in JSON: what `openlanes state sign` writes.
      class Signatures < Section
        # @return [Array<Hash>]
        def signatures = read["signatures"]

        # @param signature [OpenLanes::Plans::PlanState::Signature]
        # @return [Hash] the signature as written
        # @raise [OpenLanes::Error] when the signature does not check
        def sign!(signature)
          signature.check!
          record = signature.to_json_h
          update { |data| data["signatures"] << record }
          record
        end

        # The signatures as ledger entries, so the dispatcher reads them
        # exactly as it reads a line in plan.md. Each signature takes two line
        # numbers, the entry and its handoff, so {Ledger.handoff_after} pairs them.
        #
        # @return [OpenLanes::Plans::Ledger::Reading]
        def ledger
          entries = []
          handoffs = []
          signatures.each_with_index do |sig, index|
            line = (index * 2) + 1
            entries << entry(sig, line)
            handoffs << Ledger::Handoff.new(at: entries.last.at, next: sig["next"], file: FILENAME, line: line + 1) if sig["next"]
          end
          Ledger::Reading.new(entries:, handoffs:, problems: [])
        end

        private

        # @return [OpenLanes::Plans::Ledger::Entry]
        def entry(sig, line)
          Ledger::Entry.new(at: parse_time(sig["at"]),
            agent: sig["agent"],
            status: sig["status"],
            round: sig["round"].to_i,
            note: sig["note"],
            file: FILENAME,
            line:)
        end
      end
    end
  end
end
