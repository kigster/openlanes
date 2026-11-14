# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # What every agent event of a job carries, and the CLI it runs on.
        class Events
          # @param desk [Desk] read for invocations and the agent's profile
          def initialize(desk)
            @desk = desk
          end

          # The CLI a running agent was started on, which is what decides
          # whether its session can be resumed.
          #
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [OpenLanes::Adapters::Base]
          def adapter_for(job) = @desk.adapter_of(job.task.agent, job.task.subject)

          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [Hash{Symbol => Object}]
          def event_fields(job)
            task = job.task
            { plan: task.subject.feature.ordinal.to_s, round: task.round, agent: task.agent.name,
              invocation_start: @desk.invocations[job.key], adapter: adapter_name(job),
              model: @desk.model_for(task.agent, task.subject, root: task.root) }
          end

          # @return [String, nil]
          def adapter_name(job)
            adapter_for(job).name.to_s
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
