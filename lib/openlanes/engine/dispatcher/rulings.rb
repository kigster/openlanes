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
          busy = untouchable - arbitration.asking
          arbitration.tick(runner.in_scope.reject { busy.include?(it.feature.ordinal.to_s) }).each do |outcome|
            note = outcome.error || outcome.effects.ruling.values_at("kind", "outcome").join(": ")
            UI.log("⚖️ #{outcome.trigger}: #{note}", level: outcome.error ? :warn : :info, plan: outcome.plan)
            # A ruling moved the plan or freed it for its builders; a refused
            # one waits out its back-off, so nothing is worth a rescan for it.
            wake! unless outcome.error
          end
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
          busy = untouchable - driver.looking
          subjects = runner.in_scope.reject { busy.include?(it.feature.ordinal.to_s) }
          driver.poll(subjects).each do |settled|
            result = settled.result
            waiting = Verification::Outcome::WAITING.include?(result.kind)
            verifying[settled.plan] = result.note if waiting
            next if waiting && said_verifying[settled.plan] == result.note

            said_verifying[settled.plan] = result.note
            verifying.delete(settled.plan) unless waiting
            finished_plans.delete(settled.plan) if result.to
            # Stalled is a warning: CI pending past `ci_pending_hours` waits on
            # a person, and an info line among the waits would never be seen.
            UI.log(result.note, level: %i[rejected stalled].include?(result.kind) ? :warn : :info, plan: settled.plan)
            wake!
          end
        end
      end
    end
  end
end
