# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Assign < Step
        # Every reason a plan in play is stepped around this pass: another
        # machine's, being discarded, held by a gate, locked elsewhere, over
        # budget, or mid-rebase.
        class Refusals < Step
          # @return [OpenLanes::Plans::Dependencies, nil] this pass's, once {#prepare} ran
          attr_reader :dependencies

          # The dependency gate and the refactor gate (R6) as of this pass.
          #
          # @return [void]
          def prepare
            @dependencies = runner.dependencies(except: untouchable)
            @global_lock = runner.global_lock(except: untouchable)
            lock_clock&.call(@global_lock)
          end

          # In this order, since {#held_outside?} and the budget each say why.
          #
          # @param subject [OpenLanes::Plans::Subject]
          # @return [Boolean]
          def refused?(subject)
            ordinal = subject.feature.ordinal.to_s
            return true if runner.foreign?(subject) || discarding.key?(ordinal) || held?(subject)
            return true if locked_elsewhere?(subject) || held_outside?(subject) || refusals.include?(ordinal)

            over_budget?(subject) || rebasing?(ordinal)
          end

          private

          # Kept apart so the rule can be read, and changed, alone.
          def held?(subject)
            ordinal = subject.feature.ordinal
            !@dependencies.reason(ordinal).nil? || !@global_lock.reason(ordinal).nil?
          end

          def over_budget?(subject)
            refusal = budget_refusal(subject)
            announce_budget(subject, refusal)
            !refusal.nil?
          end

          # A stopped rebase holds the checkout until the harness has continued
          # or aborted it; a partner started now would build on conflict markers.
          def rebasing?(ordinal) = running.any? { plan_of(it) == ordinal && it.rebase }
        end
      end
    end
  end
end
