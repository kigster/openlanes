# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # deploy-assessor's verdicts for this visit to 🏁 (P1, P4), keyed by pull
      # request number, plus the moments the engine rebased a sibling (P5).
      # A visit is told apart by the plan's move count: a plan sent back and
      # brought to 🏁 again has moved since, so its old verdicts no longer stand.
      class MergeRisk < Section
        # @return [Hash, nil] `moves`, `at`, `verdicts` and `rebased`, nil when
        #   deploy-assessor has not ruled on this visit
        def merge_risk
          data = read
          record = data["merge_risk"] or return nil
          record["moves"] == data["moves"].to_i ? record : nil
        end

        # @param verdicts [Hash{Integer, String => String}]
        # @param at [Time]
        # @return [Hash] the record kept
        def assess!(verdicts, at)
          update do |data|
            data["merge_risk"] = { "moves" => data["moves"].to_i, "at" => at.iso8601,
                                   "verdicts" => verdicts.to_h { |n, v| [n.to_s, v.to_s] }, "rebased" => {} }
          end
          merge_risk
        end

        # @param number [Integer] the sibling pull request the engine rebased
        # @param at [Time]
        # @return [void]
        def rebased!(number, at)
          update { |data| data["merge_risk"]&.fetch("rebased")&.store(number.to_s, at.iso8601) }
        end
      end
    end
  end
end
