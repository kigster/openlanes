# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # The round as the executor left it: whose it was, what it said, what
        # it spent and where it wrote, before any verdict is read into it. A
        # result that is an exception says nothing and spent nothing.
        class Account < Step
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [OpenLanes::Engine::Runner::Attempt]
          def call(job)
            Runner::Attempt.new(**identity(job), **said(job.result), **Spend.of(job.result).to_h, **written(job))
          end

          private

          def identity(job)
            task = job.task
            { ordinal: task.subject.feature.ordinal.to_s, agent: task.agent.name, from: job.from, to: job.from, round: task.round }
          end

          def said(result)
            { ok: result.respond_to?(:ok) ? !!result.ok : false, note: result.respond_to?(:note) ? result.note.to_s : "" }
          end

          def written(job)
            task = job.task
            { file: job.file || task.agent.ledger.first.to_s, model: model_for(task.agent, task.subject, root: task.root), status: job.status }
          end
        end
      end
    end
  end
end
