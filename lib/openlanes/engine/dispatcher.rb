# frozen_string_literal: true

require "forwardable"
require "monitor"
require "socket"

module OpenLanes
  module Engine
    # The loop: {Ticker} runs the steps over one shared {Desk}. Nothing
    # guesses: when ledger, state machine and state file disagree, the row
    # goes red with the reason, and nobody is re-run to paper over it.
    class Dispatcher
      extend Forwardable
      include Deps["clock"]

      HARNESS = Recovery::HARNESS # who the harness signs its own mail as
      BLOCKED = %i[blocked product_blocked bomb].freeze # waiting on a person; an answered 💣 drains like ⭕
      LINGER = 10 # seconds a settled row stays on the screen
      KILL_GRACE = 15 # seconds a kill waits between STOP and SIGKILL
      TICK = 0.5 # seconds between ticks: a rename reaches the page in ~0.75 s, inside the spec's 1 s
      RESCAN_SECONDS = 5 # idle rescans, for hand edits and `openlanes create` typed elsewhere
      RESCAN = (RESCAN_SECONDS / TICK).round # the same, in ticks
      FINISHED = Live::Snapshot::FINISHED # nothing left to do; not `terminal?`, as ✅ and 😎 roll back
      REVIEW_PHASE = "review" # whose Completed notes are verdicts
      MERGE_POLL = Steps::POLL # seconds between passes over 🏁 pull requests
      # @return [Integer] an interval a person states, in ticks, at least one
      def self.ticks(seconds) = [(seconds / TICK).round, 1].max

      PUBLIC = %i[running runner attempts mail mail= rebases state_file wake! adapter_for adapter_of resume stay? job signal].freeze # the desk's public face

      # Callers pass the keywords they always have; {Options} gathers them.
      def initialize(**options)
        super(**options.slice(:clock))
        @options = Options.with_defaults(**options, clock: @clock)
        @desk = Desk.new(@options.desk_setup, clock: @clock)
        @tick_lock = Monitor.new
        @sleeper = @options.sleeper || ->(seconds) { @clock.sleep(seconds) }
        @before_tick = []
        build_collaborators
      end

      def_delegators :@desk, *Desk.public_instance_methods(false)
      private(*(Desk.public_instance_methods(false) - PUBLIC))

      def_delegators :@controls, :kill, :extend, :answer_extension, :requeue, :compact, :prefer_model, :concurrency=
      def_delegators "@ticker.rows", :board
      def_delegators "@ticker.lanes", :discard, :fence, :stop_plan, :restart_plan
      def_delegators "@ticker.assign", :idle_reason, :blockers_first
      def_delegators "@ticker.rename", :apply_hold
      def_delegators "@ticker.poll", :record_journal
      def_delegators :@restart, :reattach, :resume_stranded
      private :idle_reason, :blockers_first, :apply_hold, :record_journal, :reattach, :resume_stranded

      # @return [Array<OpenLanes::Engine::Runner::Attempt>] the run, to a fixed point or a quit
      def run
        feed.append(:run_started, jobs: runner.jobs)
        resume_stranded(reattach)
        loop do
          tick
          break if done?

          @sleeper.call(TICK)
        end
        feed.append(:run_ended, reason: Execution::Control.quit? ? "quit" : "fixed point")
        attempts
      end

      # One cycle at a time (two overlapping ones each started the same plan),
      # under a `Monitor`, so a hook that ticks from inside a tick does not deadlock.
      def tick
        @tick_lock.synchronize do
          @before_tick.each { |hook| hook.call(self) }
          @ticker.call(@restart.method(:convert_questions))
          @restart.persist
          @options.on_board&.call(board)
        end
      end

      # @return [Boolean] see {FixedPoint#reached?}
      def done? = @fixed_point.reached?

      # Run at the top of every tick, on the loop thread, where {#running} is safe to change.
      def before_tick(&hook) = @before_tick << hook

      private

      # The desk's collections and the steps, also under the names the suite reads.
      def build_collaborators
        @holds, @finished_plans, @discarding = @desk.holds, @desk.finished_plans, @desk.discarding
        @ticker = Ticker.new(@desk, @options)
        @watching = @ticker.watching
        @unblocking = @ticker.unblocking
        @controls = Controls.new(@desk)
        @restart = Restart.new(@desk, @options, start: @ticker.start)
        @conversions = @restart.conversions
        @fixed_point = FixedPoint.new(@desk, @ticker.assign)
      end
    end
  end
end
