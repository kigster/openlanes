# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # R4's question, when this plan is the one that asked it.
      class QualityAsk < Section
        # @return [Hash, nil] `asked_at`, and once answered `answer`, `by`, `settled_at`
        def quality_ask = read["quality_ask"]

        # Asking twice changes nothing, so a hand-off repeated every tick
        # keeps its first moment.
        #
        # @param at [Time]
        # @return [Hash] the ask as it stands
        def ask_quality!(at)
          update { |data| data["quality_ask"] ||= { "asked_at" => at.iso8601 } }
          quality_ask
        end

        # @param answer [String] "high", "standard" or "mvp"
        # @param by [String]
        # @param at [Time]
        # @return [Hash, nil] the ask as settled; nil when none is open
        def settle_quality_ask!(answer, by, at)
          settled = nil
          update do |data|
            ask = data["quality_ask"]
            next if ask.nil? || ask.key?("settled_at")

            settled = ask.merge!("answer" => answer.to_s, "by" => by, "settled_at" => at.iso8601)
          end
          settled
        end
      end
    end
  end
end
