# frozen_string_literal: true

module OpenLanes
  module Engine
    class Budget
      # Whether a run's dollar cap can be enforced at all (decision C11).
      #
      # Spend is summed from the event log, so a run whose log is off counts
      # $0 for every plan forever: `budget.plan_usd` would sit in the config
      # looking like a guarantee and never hold anything. A cap nobody can
      # count is refused before the run starts rather than trusted.
      class Guard
        # @param cap [Float, nil] `budget.plan_usd`; nil is no cap
        # @param events [#enabled?] the run's event sink
        def initialize(cap:, events:)
          @cap = cap
          @events = events
        end

        # @return [String, nil] why the run may not start, or nil when the cap
        #   can be counted or there is none
        def refusal
          return nil if @cap.nil? || @events.enabled?

          "budget.plan_usd is #{dollars} but events.enabled is false, so spend cannot be counted " \
            "and the cap would never hold a plan.\n\n" \
            "Enable events in .openlanes/config.yml, or remove the cap."
        end

        private

        # @return [String] `$25`, or `$2.50` for a cap with cents
        def dollars = @cap == @cap.to_i ? "$#{@cap.to_i}" : format("$%.2f", @cap)
      end
    end
  end
end
