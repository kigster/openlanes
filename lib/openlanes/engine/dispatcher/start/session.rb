# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Start < Step
        # The session this round carries on (M1): the previous round's, when
        # its CLI can resume one, the plan has not moved since, and it ran in
        # this round's checkout. Either way the log says which and why, since
        # an agent that suddenly knows or forgets everything is otherwise a
        # mystery.
        class Session < Step
          # @param task [OpenLanes::Engine::Runner::Task]
          # @param state [Symbol] the state the plan was in when dispatched
          # @return [String, nil] the session id to resume, nil to start fresh
          def resumption_for(task, state)
            return nil if runner.dry_run?

            adapter = adapter_of(task.agent, task.subject)
            return fresh(task, "#{adapter.name} cannot resume one") unless adapter.resumes?

            decided(task, decision_for(task, state, adapter))
          rescue OpenLanes::Error => e
            UI.log("fresh session: state.json unreadable: #{e.message}", level: :warn, **task.log_fields)
            nil
          end

          private

          def decision_for(task, state, adapter)
            Plans::PlanState.for(task.subject.feature.path)
                            .resumption(agent: task.agent.name, state:, root: task.root, adapter: adapter.name)
          end

          def fresh(task, why)
            UI.log("fresh session: #{why}", **task.log_fields)
            nil
          end

          def decided(task, decision)
            UI.log(decision.resume? ? "resuming session #{decision.session}: #{decision.reason}" : "fresh session: #{decision.reason}",
              **task.log_fields)
            decision.session
          end
        end
      end
    end
  end
end
