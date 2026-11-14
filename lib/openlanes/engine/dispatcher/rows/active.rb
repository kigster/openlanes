# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rows < Step
        # The row of one job still running: whose round it is, where it
        # writes, what it has spent and said. Drawing it moves the job's
        # spinner on a frame, and that is the only thing it changes.
        class Active < Step
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [OpenLanes::Engine::Board::Row]
          def call(job)
            job.frame = job.frame.to_i + 1
            Board::Row.new(key: job.key,
              at: clock.now,
              state: :running,
              **whose(job),
**where(job.task, job.file),
**spent(job),
**said(job))
          end

          private

          def whose(job)
            task = job.task
            agent = task.agent
            { ordinal: task.subject.feature.ordinal.to_s, agent: agent.name, role: agent.role, round: task.round,
              rounds: job.rounds || rounds_for(agent), model: model_for(agent, task.subject, root: task.root) }
          end

          def where(task, file)
            { file: file || task.agent.ledger.first.to_s, pr: pr_for(task),
              unacked: Board::Row.unacked_in(task.subject.feature.path) }
          end

          def spent(job)
            handle = job.handle
            { remaining: handle.remaining, phase: handle.phase, up: job.up.to_i, down: job.down.to_i,
              frame: job.frame, elapsed: (UI.monotonic - job.started_at).round, subagents: job.subagents.to_i }
          end

          def said(job)
            { message: job.message, history: job.history || [], context: job.context, since: job.started_at,
              session: job.handle.session, running: job.running || [] }
          end

          # @param task [OpenLanes::Engine::Runner::Task]
          # @return [Hash, nil]
          def pr_for(task)
            return nil unless task.agent.ledger.include?("pull-requests.md")

            subject = Plans::Tree.new(dir: runner.tree.dir).find(task.subject.feature.ordinal) or return nil
            pull = subject.pull_requests.find(&:open?) or return nil
            { number: pull.number, url: pull.url, rejected: subject.status.key == :rejected }
          end
        end
      end
    end
  end
end
