# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # The run as a screen shows it: one row per running job ({Active}), the
      # rows of jobs that settled in the last {LINGER} seconds, and the totals
      # above them. Read from the desk each tick; nothing here changes the
      # run, except that drawing a job's row moves its spinner on a frame.
      class Rows < Step
        # @param desk [Desk]
        # @param waiting_on [#call] the pull requests a person owes, by ordinal
        def initialize(desk, waiting_on:)
          super(desk)
          @waiting_on = waiting_on
          @started_at = UI.monotonic
          @active = Active.new(desk)
        end

        # @return [OpenLanes::Engine::Board::Row] see {Active#call}
        def_delegator :@active, :call, :row_for

        # The plans are read before the rows, so a settled row that lingered
        # out this tick still names its plan once more.
        #
        # @return [OpenLanes::Engine::Board]
        def board
          Board.new(started_at: @started_at,
            status: run_status,
            plans:,
            rows:,
            root: runner.root,
            waiting_on: @waiting_on.call.dup,
            jobs: runner.jobs,
            **tokens)
        end

        private

        # @return [Symbol]
        def run_status
          return :quitting if Execution::Control.quit?
          return :wrapping_up if running.any? { |j| %i[wrap_up stopped].include?(j.handle.phase) }
          return :idle if idle && quiet?

          :running
        end

        # @return [Array<String>]
        def plans
          (running.map { |j| j.task.subject.feature.ordinal.to_s } + recent.map { |r| r[:row].ordinal } +
            waiting + finishes.ordinals).uniq
        end

        # @return [Array<OpenLanes::Engine::Board::Row>]
        def rows
          now = UI.monotonic
          recent.reject! { |r| now - r[:at] > LINGER }
          running.map { |job| row_for(job) } + recent.map { |r| r[:row] }
        end

        # Spend so far: settled rounds plus what the running ones report.
        def tokens
          live_up = running.sum { |j| j.up.to_i }
          live_down = running.sum { |j| j.down.to_i }
          { up: attempts.sum(&:up) + live_up, down: attempts.sum(&:down) + live_down, live_up:, live_down:, running: running.size }
        end
      end
    end
  end
end
