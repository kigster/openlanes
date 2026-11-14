# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # The agent stopped without saying it finished. If the state it was
        # advancing to is justified by what is on disk, the work happened and
        # the harness signs for it in state.json, saying why it had to.
        class Signing < Step
          # @param desk [Desk]
          # @param rename [Rename] completes a signed round
          # @param stops [Stops]
          def initialize(desk, rename:, stops:)
            super(desk)
            @rename = rename
            @stops = stops
          end

          # @return [OpenLanes::Engine::Runner::Attempt]
          def call(job, base, reason)
            task = job.task
            subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
            # Read before the harness's own Interrupted line lands, which would
            # otherwise be the "last ledger line" the resume record quotes.
            last = last_line(subject, task.agent)
            write_interrupted(subject, task.agent, task.round, reason)
            target = task.agent.advances_to&.then { subject.machine.onward(it) }
            return sign(job, base.with(note: "#{reason}; signed by harness"), subject, target) if target && subject.machine.may?(target)

            # The reason travels as the base's note, which the outcome replaces.
            unsigned(job, base.with(note: reason), subject, last)
          end

          private

          def sign(job, base, subject, target)
            task = job.task
            successor = successor_of(target)
            Plans::PlanState.for(subject.feature.path).sign!(agent: task.agent.name,
              round: task.round,
              status: "Completed",
              note: "signed by harness: work verified on disk",
              next_agent: successor)
            reading = read_ledger(task)
            @rename.complete(job, base, Plans::Ledger.last_for(reading, task.agent.name), read_ledger(task))
          end

          def unsigned(job, base, subject, last)
            task = job.task
            reason = base.note
            harness_resume(subject, task.agent, task.round, reason, last:, phrase: job.message)
            remember(subject.feature.ordinal.to_s, task.agent.name, job.state, "Interrupted", task.round)
            note = @stops.retry_note(task.agent, interrupted_entry(task))
            base.with(ok: false, status: "Interrupted", note: "#{reason}; #{note}")
          end

          def successor_of(target) = runner.agents.for_status(Plans::STATUS_BY_KEY.fetch(target)).first&.name

          def interrupted_entry(task)
            Plans::Ledger::Entry.new(at: clock.now,
              agent: task.agent.name,
              status: "Interrupted",
              round: task.round,
              file: "",
              line: 0)
          end
        end
      end
    end
  end
end
