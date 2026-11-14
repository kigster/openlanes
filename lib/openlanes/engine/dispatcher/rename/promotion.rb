# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # A Completed round that moves its folder on: published first when the
        # move is to 🟢, then asked whether the state is justified, then moved.
        class Promotion < Step
          # Moved, or a reason it did not; `final` when the `next:` line is
          # not to be honoured.
          Moved = Data.define(:attempt, :final)

          # @param desk [Desk]
          # @param publication [Publication]
          def initialize(desk, publication:)
            super(desk)
            @publication = publication
          end

          # @param round [Completed]
          # @param attempt [OpenLanes::Engine::Runner::Attempt]
          # @param target [Symbol]
          # @return [Moved]
          def call(round, attempt, target)
            published = @publication.call(round.job.task, target, round.subject, noted(round, attempt))
            return Moved.new(attempt: untestable(round.job, published.attempt, round.subject), final: true) if published.untestable
            return Moved.new(attempt: unpublished(published, round.ordinal), final: true) if published.refused

            onward(round.job, published, target)
          end

          private

          # The closing note goes on the attempt, after the base's own.
          def noted(round, attempt) = attempt.with(note: "#{round.base.note}#{" (#{round.entry.note})" if round.entry.note}")

          def onward(job, published, target)
            subject = published.subject
            target = subject.machine.onward(target)
            return Moved.new(attempt: unjustified(job, published.attempt, subject, target), final: true) unless subject.machine.may?(target)

            subject.machine.promote!(target)
            Moved.new(attempt: published.attempt.with(to: target), final: false)
          end

          # The agent signed Completed, but what it left does not justify the
          # state it advances to. The folder stays, its `next:` is not
          # honoured, and the round is recorded as Interrupted; once the
          # agent's rounds run out, Needs you asks for more of them (E1).
          def unjustified(job, attempt, subject, target)
            status = Plans::STATUS_BY_KEY.fetch(target)
            remember(plan_of(job), job.task.agent.name, job.state, "Interrupted", job.task.round)
            attempt.with(ok: false,
              status: "Interrupted",
              note: "ledger says Completed but #{status} is not justified: #{status.violation(subject)}")
          end

          # plan.md says nothing about how to test the result. That is work an
          # agent can do, so the builder is mailed what is missing and handed
          # its round back, once, to write it. A second refusal is Interrupted
          # and spends a round, as any failed round does.
          def untestable(job, attempt, subject)
            agent = job.task.agent
            return asked(job, attempt, subject) if mutex.synchronize { asked_how_to_test.add?(plan_of(job)) }

            remember(plan_of(job), agent.name, job.state, "Interrupted", job.task.round)
            attempt.with(status: "Interrupted", note: "#{attempt.note}; still missing after #{agent.name} was asked")
          end

          def asked(job, attempt, subject)
            forget_round(job)
            Plans::Mailbox.new(dir: subject.feature.path).append(from: HARNESS, to: job.task.agent.name, body: HOW_TO_TEST_MAIL)
            attempt.with(status: "Interrupted", note: "#{attempt.note}; #{job.task.agent.name} was asked to add it")
          end

          # A refused publish leaves the plan where it was, done for this run:
          # running the builder again would only hit the same rejected push.
          def unpublished(published, ordinal)
            finished_plans << ordinal
            published.attempt
          end
        end
      end
    end
  end
end
