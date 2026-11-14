# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # A reviewer that crashed, timed out or ended without a verdict runs
        # its round again, once, on the main coding agent, and that verdict
        # counts as its own (D14 in plan 031). The round is handed back, so
        # the replacement runs even when the reviewer had none left; the
        # replacement's own failure is an ordinary one. A person's stop, the
        # harness's, and a plan that has left review are not failures to make
        # up for.
        class Replacement < Step
          # @param desk [Desk]
          # @param stops [Stops]
          def initialize(desk, stops:)
            super(desk)
            @stops = stops
          end

          # @param result [OpenLanes::Execution::Executor::Result, Exception]
          # @return [OpenLanes::Engine::Runner::Attempt]
          def call(job, attempt, result)
            agent = job.task.agent
            return attempt unless agent.phase.to_s == REVIEW_PHASE && executor.respond_to?(:replace)
            return ended(job, attempt) if executor.replacing?(plan_of(job), agent.name)
            return attempt unless replaceable?(job, attempt, result)

            replace(job, attempt)
          end

          # A new review round opened: a replacement the last one owed is dropped.
          #
          # @param ordinal [String]
          # @return [void]
          def end_replacements(ordinal)
            return unless executor.respond_to?(:end_replacements)

            executor.end_replacements(ordinal)
            models.delete_if { |(plan, _), _| plan == ordinal }
          end

          private

          def executor = runner.executor

          def ended(job, attempt)
            executor.replace(plan_of(job), job.task.agent.name, on: false)
            forget_model(job)
            attempt
          end

          def replace(job, attempt)
            task = job.task
            main = Agents::Dealing.current.main
            executor.replace(plan_of(job), task.agent.name)
            forget_model(job)
            resume(plan_of(job), task.agent.name)
            say(task, main)
            attempt.with(note: "#{attempt.note}; runs again on #{main}")
          end

          def say(task, main)
            fresh(task)&.then { stage!(it, task.agent, task.round, replaced_by: main) }
            UI.log("runs again on #{main}", **task.log_fields)
          end

          def forget_model(job) = models.delete([plan_of(job), job.task.agent.name])

          # @return [Boolean] whether the attempt failed in a way {#call} makes up for
          def replaceable?(job, attempt, result)
            return false if attempt.ok || attempt.status.to_s.start_with?("Blocked")
            return false if @stops.stopped_for(plan_of(job)) || Execution::Control.interrupted?
            return false if result.respond_to?(:killed) && %i[key quit].include?(result.killed)

            %i[ready_for_review in_review].include?(fresh(job.task)&.status&.key)
          end
        end
      end
    end
  end
end
