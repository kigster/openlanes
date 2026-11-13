# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # The run as a screen shows it: one row per running job, the rows of
      # jobs that settled in the last {LINGER} seconds, and the totals above
      # them. Read from the desk each tick; nothing here changes the run,
      # except that drawing a job's row moves its spinner on a frame.
      class Rows < Step
        # @param desk [Desk]
        # @param waiting_on [#call] the pull requests a person owes, by ordinal
        def initialize(desk, waiting_on:)
          super(desk)
          @waiting_on = waiting_on
          @started_at = UI.monotonic
        end

        # @return [OpenLanes::Engine::Board]
        def board
          up = attempts.sum(&:up) + running.sum { |j| j.up.to_i }
          down = attempts.sum(&:down) + running.sum { |j| j.down.to_i }
          Board.new(started_at: @started_at,
            status: run_status,
            plans: (running.map { |j| j.task.subject.feature.ordinal.to_s } + recent.map { |r| r[:row].ordinal } +
                    waiting + finishes.ordinals).uniq,
            up:,
            down:,
            rows: rows,
            root: runner.root,
            running: running.size,
            live_up: running.sum { |j| j.up.to_i },
            live_down: running.sum { |j| j.down.to_i },
            waiting_on: @waiting_on.call.dup,
            jobs: runner.jobs)
        end

        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [OpenLanes::Engine::Board::Row]
        def row_for(job)
          task = job.task
          job.frame = job.frame.to_i + 1
          Board::Row.new(key: job.key,
            at: clock.now,
            ordinal: task.subject.feature.ordinal.to_s,
            file: job.file || task.agent.ledger.first.to_s,
            agent: task.agent.name,
            role: task.agent.role,
            round: task.round,
            rounds: job.rounds || rounds_for(task.agent),
            model: model_for(task.agent, task.subject),
            remaining: job.handle.remaining,
            phase: job.handle.phase,
            up: job.up.to_i,
            down: job.down.to_i,
            message: job.message,
            state: :running,
            pr: pr_for(task),
            frame: job.frame,
            elapsed: (UI.monotonic - job.started_at).round,
            subagents: job.subagents.to_i,
            history: job.history || [],
            context: job.context,
            since: job.started_at,
            session: job.handle.session,
            unacked: Board::Row.unacked_in(task.subject.feature.path),
            running: job.running || [])
        end

        private

        # @return [Symbol]
        def run_status
          return :quitting if Execution::Control.quit?
          return :wrapping_up if running.any? { |j| %i[wrap_up stopped].include?(j.handle.phase) }
          return :idle if idle && quiet?

          :running
        end

        # @return [Array<OpenLanes::Engine::Board::Row>]
        def rows
          now = UI.monotonic
          recent.reject! { |r| now - r[:at] > LINGER }
          running.map { |job| row_for(job) } + recent.map { |r| r[:row] }
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
