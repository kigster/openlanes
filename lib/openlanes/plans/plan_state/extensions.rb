# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # Requests for more time or another round for one agent (E1), and how
      # each was answered. Kept in the file, so a grant survives a restart and
      # an answer can come from any control room.
      class Extensions < Section
        # @return [Array<Hash>] oldest first; empty for a plan that never asked
        def extensions = read["extensions"] || []

        # @param ask [OpenLanes::Plans::PlanState::ExtensionAsk]
        # @param fields [Hash] `stage`, a grant made outright, or `cause`
        # @return [Hash] the request as written, with its `number`
        def ask_extension!(ask, fields)
          record = nil
          update do |data|
            all = (data["extensions"] ||= [])
            record = ask.to_json_h((all.map { it["number"] }.max || 0) + 1, data["moves"].to_i)
                        .merge(fields.transform_keys(&:to_s).compact)
            all << record
          end
          record
        end

        # The agent's own estimate (E2), written onto the request still at its
        # `estimate` stage; one that arrives after the engine stopped waiting
        # changes nothing, and its arguments are not even read: `&.` skips them.
        #
        # @param agent [String]
        # @param seconds [Integer, String]
        # @param why [String, nil]
        # @param at [Time]
        # @return [Hash, nil] the request as it now stands
        def estimate_extension!(agent, seconds, why, at)
          found = nil
          update do |data|
            found = (data["extensions"] || []).find do |request|
              request["agent"] == agent && request["stage"] == "estimate" && !request.key?("settled_at")
            end
            found&.merge!({ "estimate" => Integer(seconds), "why" => why, "estimated_at" => at.iso8601 }.compact)
          end
          found
        end

        # Answer a request, or close it unanswered. Once settled it stays
        # settled. A request asked before requests named their visit is
        # stamped with the visit it is answered in.
        #
        # @param number [Integer]
        # @param at [Time]
        # @param fields [Hash]
        # @return [Hash, nil] the request as settled; nil when none, or settled already
        def settle_extension!(number, at, fields)
          settled = nil
          update do |data|
            found = find(data, number) or next
            next if found.key?("settled_at")

            found["moves"] = data["moves"].to_i unless found.key?("moves")
            settled = found.merge!(fields.transform_keys(&:to_s).compact, "settled_at" => at.iso8601)
          end
          settled
        end

        # @param number [Integer]
        # @param fields [Hash]
        # @return [Hash, nil] the request as it now stands
        def amend_extension!(number, fields)
          amended = nil
          update { |data| amended = find(data, number)&.merge!(fields.transform_keys(&:to_s)) }
          amended
        end

        # @param number [Integer]
        # @return [void]
        def spend_extension!(number)
          update { |data| find(data, number)&.store("spent", true) }
        end

        private

        # @return [Hash, nil]
        def find(data, number) = (data["extensions"] || []).find { it["number"] == Integer(number) }
      end
    end
  end
end
