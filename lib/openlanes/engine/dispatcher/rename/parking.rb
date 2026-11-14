# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # Rounds whose folder does not move on: a question parks the plan in
        # ⭕ or 🛑, and deploy-assessor's ruling is the engine's to act on.
        class Parking < Step
          # @return [OpenLanes::Engine::Runner::Attempt]
          def park(job, base, entry)
            subject = fresh(job.task) or return base.with(ok: false, note: "plan folder vanished")
            target = Verdicts.of(entry) == :product ? :product_blocked : :blocked
            asked(job, subject, target)
            parked(base, subject, target)
          end

          # deploy-assessor finished, or stopped without a verdict. The engine
          # labels, merges and rebases from here; the folder moves only to ✅ or 🔴.
          #
          # @param note [String, nil] the Completed note; nil leaves every pull request unassessed
          # @return [OpenLanes::Engine::Runner::Attempt]
          def assessed(job, base, note)
            task = job.task
            subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
            remember(plan_of(job), task.agent.name, job.state, "Completed", task.round)
            settled(job, base, runner.merging.assess(subject, note))
          rescue OpenLanes::Error => e
            base.with(ok: false, status: "Completed", note: "#{base.note}; merge not settled: #{e.message}")
          end

          private

          def asked(job, subject, target)
            ordinal = subject.feature.ordinal.to_s
            remember(ordinal, job.task.agent.name, job.state, "Blocked", job.task.round)
            feed.append(:question, plan: ordinal, agent: job.task.agent.name, note: target.to_s)
          end

          def settled(job, base, result)
            wake!
            base.with(status: "Completed", to: result.to || job.state, note: "#{base.note}; #{result.note}")
          end

          def parked(base, subject, target)
            unless subject.machine.may?(target)
              return base.with(ok: false,
                status: "Blocked",
                note: "ledger says Blocked but #{Plans::STATUS_BY_KEY.fetch(target).violation(subject)}")
            end

            subject.machine.promote!(target)
            base.with(to: target, status: "Blocked", note: "blocked; see blocked.md")
          end
        end
      end
    end
  end
end
