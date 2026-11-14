# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # The durable record of one settled attempt: `agent_finished` always,
        # `block_raised` when the agent signed Blocked, `failure` when the
        # attempt failed. Fire and forget: the sink never raises.
        class Announcement < Step
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @param attempt [OpenLanes::Engine::Runner::Attempt]
          # @return [void]
          def call(job, attempt)
            fields = event_fields(job)
            invocations.delete(job.key)
            record(job, fields, attempt) if runner.events.enabled?
          rescue StandardError => e
            UI.log("event not recorded", plan: job.task.subject.feature.ordinal.to_s, error: e.class.name)
          end

          private

          def record(job, fields, attempt)
            status = attempt.status || (attempt.ok ? "Completed" : "Interrupted")
            finished(fields, attempt, status)
            runner.events.record(:block_raised, **fields, blocks: blocked_count(job)) if status.start_with?("Blocked")
            failure(job, fields) unless attempt.ok
          end

          def finished(fields, attempt, status)
            usage = Events::Usage.from(adapter: fields[:adapter],
              model: fields[:model],
              totals: { up: attempt.up, down: attempt.down },
              subagents_spawned: attempt.subagents.to_i)
            runner.events.record(:agent_finished,
**fields,
              status:,
              duration_s: attempt.seconds,
              **usage.to_h.transform_keys(&:to_sym))
          end

          def failure(job, fields)
            error = job.result.is_a?(Exception) ? job.result.class.name : "AttemptFailed"
            runner.events.record(:failure, **fields, error_class: error)
          end

          # @return [Integer] the open `## B<n>` questions the plan now carries
          def blocked_count(job)
            subject = fresh(job.task) or return 0
            path = File.join(subject.feature.path, "blocked.md")
            File.file?(path) ? File.read(path).scan(Plans::OPEN_BLOCK).size : 0
          end
        end
      end
    end
  end
end
