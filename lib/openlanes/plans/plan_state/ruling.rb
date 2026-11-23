# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # One arbitrator ruling as {PlanState#rule!} receives it, before it is
      # written: `pr`, `round` and `review` are coerced to integers, and
      # empty fields are dropped. Every field is required: the defaults live on
      # the facade's keywords, the one place a caller reads them.
      Ruling = Data.define(:kind, :pr, :round, :outcome, :findings, :winner, :reason, :trigger, :review, :at) do
        # @return [Hash] in the key order `state.json` has always carried
        def to_json_h
          { **head, "findings" => findings_h, "winner" => winner, "reason" => reason.to_s, "trigger" => trigger.to_s,
            "review" => review && Integer(review) }.compact
        end

        private

        # @return [Hash] the fields before `findings`
        def head
          { "at" => at.iso8601, "kind" => kind.to_s, "pr" => pr && Integer(pr), "round" => round && Integer(round),
            "outcome" => outcome.to_s }
        end

        # @return [Hash] struck, critical and, when known, headings
        def findings_h
          ids = (findings || {}).transform_keys(&:to_s)
          headings = (ids["headings"] || {}).to_h { |id, heading| [id.to_s, heading.to_s] }
          { "struck" => Array(ids["struck"]).map(&:to_s), "critical" => Array(ids["critical"]).map(&:to_s),
            "headings" => (headings unless headings.empty?) }.compact
        end
      end
    end
  end
end
