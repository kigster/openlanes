# frozen_string_literal: true

module OpenLanes
  module Supervision
    # `openlanes start` (S1): spawns the engine and the web as children and
    # does nothing else. It restarts whichever crashes, with backoff, gives up
    # on one that crashes {Crashes::LIMIT} times inside {Crashes::WINDOW}, and
    # stops both when told to. The engine ending of its own accord (Stop All
    # Local, a refusal) ends the factory with the engine's status.
    #
    # A child that exits and leaves its PID file behind crashed; one that
    # removed it meant to stop ({Registration#hold}). Every child is in a
    # process group of its own, so the Ctrl-C that reaches this process
    # reaches no child, and the order stays this one's to give.
    class Supervisor
      # Seconds the children get after TERM: the engine's own quit grace,
      # for agents to write down where they got to, and a margin for it to
      # reap them.
      GRACE = Execution::Control::GRACE + 15

      # Seconds between looks at the children.
      TICK = 0.2

      # Seconds between title refreshes.
      TITLE_EVERY = 5

      # @param programs [Array<OpenLanes::Supervision::Program>]
      # @param registration [OpenLanes::Supervision::Registration] this process's own
      # @param lifeline [OpenLanes::Supervision::Lifeline]
      # @param host [OpenLanes::Supervision::Host]
      def initialize(programs:, registration:, lifeline: Lifeline.open, host: Host::SYSTEM)
        @slots = programs.map { Slot.new(it, Crashes.new(clock: host.clock)) }
        @registration = registration
        @lifeline = lifeline
        @host = host
        @stopping = false
        @forced = false
        @status = nil
      end

      # @return [Array<Slot>]
      attr_reader :slots

      # Starts every child, then watches them until told to stop or until
      # nothing is left to watch.
      #
      # @yieldparam supervisor [Supervisor] once a tick, after the children are seen to
      # @return [Integer] the exit status: the engine's when it ended the
      #   factory, 1 when every child was given up on, else 0
      def call(&on_tick)
        @on_tick = on_tick
        @started = clock.monotonic
        @slots.each { start(it) }
        watch
        Shutdown.new(@slots, host: @host).call(grace: GRACE) { @forced }
        @status || 0
      ensure
        @lifeline.cut
      end

      # Asked from a signal trap, so it only sets flags. The second time
      # means now: KILL rather than wait out {GRACE}.
      #
      # @return [void]
      def stop!
        @forced = true if @stopping
        @stopping = true
      end

      # One look at the children. Public so a spec can drive it.
      #
      # @return [void]
      def tick
        @slots.each do |slot|
          reap(slot)
          start(slot) if slot.due?(clock.monotonic) && !@stopping
        end
        finished unless @stopping
        retitle
        @on_tick&.call(self)
      end

      private

      # @return [#monotonic, #sleep]
      def clock = @host.clock

      # Ticks until told to stop, or until nothing is left to watch.
      #
      # @return [void]
      def watch
        until @stopping
          tick
          clock.sleep(TICK)
        end
      end

      # @param slot [Slot]
      # @return [void]
      def start(slot)
        slot.due = nil
        program = slot.program
        slot.pid = @host.spawner.spawn(program.env.merge(@lifeline.env),
          *program.argv,
          pgroup: true,
          in:     File::NULL,
          **@lifeline.options,
          **program.options)
        Log.logger.info("child started", role: slot.role, pid: slot.pid, restarts: slot.restarts)
      end

      # @param slot [Slot]
      # @return [void]
      def reap(slot)
        return unless slot.running?

        status = @host.waiter.call(slot.pid) or return
        crashed = crashed?(slot)
        pid = slot.pid
        slot.pid = nil
        return if @stopping

        crashed ? crash(slot, status, pid) : ended(slot, status)
      end

      # Its PID file outlived it.
      #
      # @param slot [Slot]
      # @return [Boolean]
      def crashed?(slot) = @registration.dir.read(slot.role)&.pid == slot.pid

      # @param slot [Slot]
      # @param status [Process::Status, Symbol]
      # @param pid [Integer]
      # @return [void]
      def crash(slot, status, pid)
        Log.logger.warn("child crashed", role: slot.role, pid:, status: Host.describe(status))
        slot.crashes.record
        return give_up(slot, slot.crashes.reason) if slot.crashes.exhausted?

        slot.restarts += 1
        slot.due = clock.monotonic + slot.crashes.delay
      end

      # It stopped on purpose. The engine stopping is the factory stopping;
      # a web that stops is left stopped, since restarting it would only
      # meet whatever stopped it again.
      #
      # @param slot [Slot]
      # @param status [Process::Status, Symbol]
      # @return [void]
      def ended(slot, status)
        code = status.respond_to?(:exitstatus) ? status.exitstatus.to_i : 0
        Log.logger.info("child ended", role: slot.role, status: code)
        return give_up(slot, "exited #{code}") unless slot.program.essential

        @status = code
        @stopping = true
      end

      # @param slot [Slot]
      # @param reason [String]
      # @return [void]
      def give_up(slot, reason)
        slot.given_up = reason
        Log.logger.error("child given up", role: slot.role, reason:)
        @registration.update(failed: @slots.select(&:given_up).to_h { [it.role, it.given_up] })
      end

      # Nothing running and nothing due: there is nothing left to supervise.
      #
      # @return [void]
      def finished
        return if @slots.any? { it.running? || it.due }

        @status ||= 1
        @stopping = true
      end

      # @return [void]
      def retitle
        now = clock.monotonic
        return if @titled && now - @titled < TITLE_EVERY

        @titled = now
        @registration.title(Title.supervising(uptime: (now - @started).to_i,
          restarts: @slots.sum(&:restarts),
          down: @slots.select(&:given_up).map(&:role)))
      end
    end
  end
end
