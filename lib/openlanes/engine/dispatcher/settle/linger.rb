# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # A settled job's row, left on the board for {LINGER} seconds, and its
        # one line in the log.
        class Linger < Step
          # @param desk [Desk]
          # @param row [#call] a job's row on the board
          def initialize(desk, row:)
            super(desk)
            @row = row
          end

          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @param attempt [OpenLanes::Engine::Runner::Attempt]
          # @return [void]
          def call(job, attempt)
            row = @row.call(job)
            recent << { at: UI.monotonic, row: row.with(state: attempt.ok ? :done : :failed,
              message: attempt.note,
              history: Board::Row.remember(row.history, attempt.note),
              remaining: nil,
              phase: nil,
              running: [],
              bold: !attempt.ok) }
            log(job, attempt)
          end

          private

          # `to:` names the state the plan moved to, on the terminal and in the log.
          def log(job, attempt)
            moved = Plans::STATUS_BY_KEY[attempt.to]&.to_s if attempt.advanced?
            UI.log(attempt.ok ? "finished: #{attempt.note}" : "failed: #{attempt.note}",
              level: attempt.ok ? :info : :warn,
              **job.task.log_fields,
              **{ to: moved }.compact)
          end
        end
      end
    end
  end
end
