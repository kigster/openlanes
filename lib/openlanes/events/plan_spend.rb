# frozen_string_literal: true

module OpenLanes
  module Events
    # What one plan has spent, summed from the event log, against its cap.
    #
    # Derived on every ask and never stored: the log already holds each run's
    # `cost_usd`, and a running total kept beside it would be a second copy
    # that drifts the first time a node's file arrives late. A run whose
    # adapter prices nothing is counted in `unpriced_runs`, never added as
    # $0, for the same reason {Usage} keeps its cost nil.
    #
    # @!attribute [r] ordinal
    #   @return [String]
    # @!attribute [r] usd
    #   @return [Float] estimated dollars, rounded to 4 places
    # @!attribute [r] unpriced_runs
    #   @return [Integer]
    # @!attribute [r] cap
    #   @return [Float, nil] `budget.plan_usd`; nil is no cap
    PlanSpend = Data.define(:ordinal, :usd, :unpriced_runs, :cap) do
      # @return [Boolean] whether the plan has reached its cap; never with no cap
      def over? = !cap.nil? && usd >= cap

      # @return [Float, nil] spend as a fraction of the cap; nil with no cap
      def share = cap && (usd / cap).round(4)

      # @return [String, nil] the hold reason, e.g. `over budget: $5.12 of $5.00`
      def reason = over? ? "over budget: #{dollars(usd)} of #{dollars(cap)}" : nil

      # @return [String] e.g. `$5.00`
      def dollars(amount) = format("$%.2f", amount)

      # @return [Hash{Symbol => Object}] the snapshot's `spend`
      def wire = { usd:, cap:, over: over?, unpriced_runs: }
    end

    class PlanSpend
      # The kind whose payload carries a run's cost.
      FINISHED = "agent_finished"

      class << self
        # @param ordinal [String, #to_s]
        # @param events [Array<OpenLanes::Events::Event>]
        # @param cap [Float, nil]
        # @return [OpenLanes::Events::PlanSpend]
        def for(ordinal, events, cap: nil)
          key = ordinal.to_s
          runs = events.select { it.kind == FINISHED && it.plan.to_s == key }
          costs = runs.map { it.payload["cost_usd"] }
          new(ordinal: key,
            usd:           costs.compact.sum(0.0).round(4),
            unpriced_runs: costs.count(&:nil?),
            cap:)
        end

        # The one place that reads `budget.plan_usd`.
        #
        # @param config [OpenLanes::Config]
        # @return [Float, nil]
        def cap_for(config) = config.budget_plan_usd
      end
    end
  end
end
