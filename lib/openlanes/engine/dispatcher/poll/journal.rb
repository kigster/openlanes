# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Poll < Step
        # The journal lines (M2) the agent printed since the last look, into
        # the plan's `state.json`, as they arrive rather than when the round
        # ends, so a round that is killed keeps what it already said. The
        # executor's thread only collects them; writing happens here, on the
        # loop's, against the folder as it is named now.
        #
        # A line that is not a valid entry is dropped and said so in the log:
        # the agent believes it remembered it, and only the log can tell a
        # person it did not.
        #
        # The place in the list moves on only once the lines are written. A
        # folder not found this tick, or a `state.json` that cannot be written
        # right now, leaves them for the next tick to try again, rather than a
        # hole in the journal the agent believes it kept.
        class Journal < Step
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [void]
          def call(job)
            lines = job.journal || []
            return unless due?(job, lines)

            entries, rejected = lines[job.journaled.to_i..].partition { it.is_a?(Plans::Journal::Entry) }
            refused = entries.empty? ? [] : written(job, entries)
            return unless refused

            job.journaled = lines.size
            ignored(job, rejected + refused)
          rescue SystemCallError, OpenLanes::Error => e
            UI.log("journal not written yet: #{e.message}", level: :warn, **job.task.log_fields)
          end

          private

          def due?(job, lines) = !(job.rebase || runner.dry_run? || lines.size <= job.journaled.to_i)

          def ignored(job, lines)
            lines.each { UI.log("journal line ignored, #{it.reason}: #{it.line[0, 160]}", level: :warn, **job.task.log_fields) }
          end

          # @return [Array, nil] the lines `state.json` refused; nil when the
          #   folder was not found, so the lines wait for the next tick
          def written(job, entries)
            subject = fresh(job.task) or return missing(job)

            job.journal_round, refused = Plans::PlanState.for(subject.feature.path)
                                                         .journal!(agent: job.task.agent.name,
                                                           entries:,
                                                           number: job.journal_round,
                                                           round: job.task.round,
                                                           state: job.from)
            refused
          end

          def missing(job)
            UI.log("journal not written yet: plan folder not found", level: :warn, **job.task.log_fields)
            nil
          end
        end
      end
    end
  end
end
