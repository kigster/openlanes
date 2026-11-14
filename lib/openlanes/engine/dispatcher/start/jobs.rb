# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Start < Step
        # A {Job} as the board first shows it, the handle its executor is
        # steered through, and the progress the executor reports onto it.
        class Jobs < Step
          # @param task [OpenLanes::Engine::Runner::Task]
          # @param handle [OpenLanes::Execution::Executor::Handle]
          # @param fields [Hash] `from:`, `state:`, and `rounds:` or `sweep:`
          # @return [OpenLanes::Engine::Dispatcher::Job]
          def build(task, handle, **fields)
            Job.new(key: "#{task.subject.feature.ordinal}/#{task.agent.name}",
              task:,
              handle:,
              started_at: UI.monotonic,
              up: 0,
              down: 0,
              subagents: 0,
              frame: 0,
**fields)
          end

          # A handle whose restarts are written into the stage (B5 in plan
          # 041); without a state file, as under a dry run, nothing is.
          #
          # @return [OpenLanes::Execution::Executor::Handle]
          def handle(ordinal, agent, round)
            Execution::Executor::Handle.new.tap do |made|
              made.on_restart = state_file && ->(fields) { state_file.restart(ordinal, agent: agent.name, round:, **fields) }
            end
          end

          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [Proc] what the executor tells of the agent's progress, onto the job
          def progress_of(job)
            lambda do |progress|
              counts(job, progress)
              job.running = progress.running
              job.context = progress.context
              said(job, progress.message || progress.activity)
              job.journal = progress.journal
            end
          end

          # @param job [OpenLanes::Engine::Dispatcher::Job] a rebase resolution
          # @return [Proc] the resolver's progress, onto the job
          def rebase_progress_of(job)
            lambda do |progress|
              job.up = progress.up
              job.down = progress.down
              said(job, "rebasing: #{progress.message || progress.activity}")
            end
          end

          # Marks a job as resolving its stopped rebase, and says so.
          #
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [void]
          def rebasing(job)
            stopped = job.rebase = job.task.refresh
            job.message = "rebasing onto #{stopped.base}: #{stopped.files.size} conflicted file#{"s" unless stopped.files.size == 1}"
            UI.log("started rebase resolution", **job.task.log_fields)
          end

          # The rebase resolved, run on the job's own thread: its result or
          # error, and the plan's lock let go whichever it was.
          #
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @param ordinal [String]
          # @return [Object, StandardError]
          def resolve(job, ordinal)
            rebases.resolve(job.task, handle: job.handle, &rebase_progress_of(job))
          rescue StandardError => e
            e
          ensure
            locks.release(ordinal)
          end

          private

          def counts(job, progress)
            job.up = progress.up
            job.down = progress.down
            job.subagents = progress.subagents
          end

          def said(job, message)
            job.message = message
            job.history = Board::Row.remember(job.history || [], message)
          end
        end
      end
    end
  end
end
