# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # What an ordinary round adds up to: the agent's closing ledger line
        # read against the executor's result and the harness's own stops.
        class Verdict < Step
          # @param desk [Desk]
          # @param rename [Rename] completes, parks and assesses rounds
          # @param stops [Stops]
          # @param signing [Signing]
          def initialize(desk, rename:, stops:, signing:)
            super(desk)
            @rename = rename
            @stops = stops
            @signing = signing
          end

          # @return [OpenLanes::Engine::Runner::Attempt] with unreadable ledger
          #   lines noted and `to:` the state the folder is in now
          def call(job, base)
            reading = read_ledger(job.task)
            attempt = noted(decide(job, base, entry_for(job.task, reading), reading), reading)
            attempt.with(to: fresh(job.task)&.status&.key || attempt.to)
          end

          private

          # This round's closing line, or nil when the last one is an earlier round's.
          def entry_for(task, reading)
            entry = Plans::Ledger.last_for(reading, task.agent.name)
            entry if entry.nil? || entry.round == task.round
          end

          def noted(attempt, reading)
            problems = reading.problems.map { |p| "#{p.file}:#{p.line} unreadable ledger line" }
            problems.empty? ? attempt : attempt.with(note: "#{attempt.note}; #{problems.join(", ")}")
          end

          # Killed, or ended well with no closing line: the harness checks the disk.
          def unsigned?(result, entry) = result.killed || (result.ok && (entry.nil? || entry.status == "Started"))

          def decide(job, base, entry, reading)
            result = job.result
            if (why = @stops.stopped_for(plan_of(job))) then @stops.stopped_by_harness(job, base, why)
            elsif assessor?(job.task.agent) && !(result.ok && entry&.completed?) then unassessed(job, base)
            elsif unsigned?(result, entry) then @signing.call(job, base, @stops.reason_for(result))
            elsif !result.ok then failed(job, base)
            else signed(job, base, entry, reading)
            end
          end

          # No verdict is `manual` (P4), never a second try at `auto`.
          def unassessed(job, base)
            task = job.task
            write_interrupted(fresh(task), task.agent, task.round, @stops.reason_for(job.result)) if fresh(task) && job.result.killed
            @rename.assessed(job, base, nil)
          end

          def failed(job, base)
            task = job.task
            fresh(task)&.then { harness_resume(it, task.agent, task.round, job.result.note, phrase: job.message) }
            remember(plan_of(job), task.agent.name, job.state, "Interrupted", task.round)
            base.with(ok: false, note: job.result.note)
          end

          def signed(job, base, entry, reading)
            return @rename.complete(job, base, entry, reading) if entry.completed?
            return @rename.park(job, base, entry) if entry.blocked?

            remember(plan_of(job), job.task.agent.name, job.state, entry.status, job.task.round)
            base.with(status: entry.status, note: @stops.retry_note(job.task.agent, entry))
          end
        end
      end
    end
  end
end
