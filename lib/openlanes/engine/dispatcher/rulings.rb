# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What came back from work done off the loop's thread: the
      # arbitrator's rulings (plan 015) and the looks at the verified plans'
      # CI (plan 014). Both are applied here, on the loop's thread, before
      # anything is assigned, and each wakes the run for the plans it moved.
      class Rulings < Step
        # The arbitrator's step (plan 015): every plan nothing is running on is
        # asked for a trigger, and a ruling that came back is applied before
        # anything is assigned, so a capped plan never reaches its builders.
        # The agent itself runs off this thread; see {Arbitration#tick}.
        #
        # @return [void]
        def arbitrate
          arbitration = runner.arbitration or return
          return if runner.dry_run?

          # The plans being asked about are untouchable to everything but the
          # ruling, which is about to be applied.
          arbitration.tick(free_but(arbitration.asking)).each { ruled(it) }
        end

        # What the last look at CI found for the verified plans, logged, and
        # the plans it moved woken for. A rejection hands the plan back to the
        # builders; `ready-to-merge` leaves it at 🧪 for a person, or plan
        # 033's merge, to finish.
        #
        # @return [void]
        def settle_verifications
          driver = runner.verification or return
          return if runner.dry_run?

          # The plans being looked at are untouchable to everything but the
          # look itself, which is about to be acted on.
          driver.poll(free_but(driver.looking)).each { looked(it) }
        end

        private

        # The plans in scope nothing else is touching, `own` aside.
        def free_but(own)
          busy = untouchable - own
          runner.in_scope.reject { busy.include?(it.feature.ordinal.to_s) }
        end

        def ruled(outcome)
          note = outcome.error || outcome.effects.ruling.values_at("kind", "outcome").join(": ")
          UI.log("⚖️ #{outcome.trigger}: #{note}", level: outcome.error ? :warn : :info, plan: outcome.plan)
          # A ruling moved the plan or freed it for its builders; a refused
          # one waits out its back-off, so nothing is worth a rescan for it.
          wake! unless outcome.error
        end

        def looked(settled)
          plan = settled.plan
          result = settled.result
          waiting = Verification::Outcome::WAITING.include?(result.kind)
          verifying[plan] = result.note if waiting
          return if waiting && said_verifying[plan] == result.note

          reported(plan, result, waiting)
          wake!
        end

        def reported(plan, result, waiting)
          said_verifying[plan] = result.note
          verifying.delete(plan) unless waiting
          finished_plans.delete(plan) if result.to
          # Stalled is a warning: CI pending past `ci_pending_hours` waits on
          # a person, and an info line among the waits would never be seen.
          UI.log(result.note, level: %i[rejected stalled].include?(result.kind) ? :warn : :info, plan:)
        end
      end
    end
  end
end
