# frozen_string_literal: true

module OpenLanes
  module Supervision
    # `openlanes stop` (S2): a stop signal to each process a PID file names,
    # a wait, then KILL. Nothing is signalled before {Probe#verified?} says it is the
    # process the file names; a file that fails the check is a crash's
    # leftover, and is removed instead.
    class Stopper
      # What became of one PID file.
      #
      # @!attribute [r] file
      #   @return [OpenLanes::Supervision::PidFile, nil] nil when unreadable
      # @!attribute [r] path
      #   @return [String]
      # @!attribute [r] result
      #   @return [Symbol] :stopped, :killed, :stale, or :would_stop under a dry run
      Outcome = Data.define(:file, :path, :result)

      # Seconds a process gets after TERM, about ten as S2 has it.
      WAIT = 10

      # Seconds a process gets after the second stop signal, which an engine
      # or a run takes as a second Ctrl-C: it KILLs its agents' groups and exits.
      HURRIED_WITHIN = Execution::Child::TERM_GRACE + 5

      # Roles a plain `stop` leaves alone: a run is its own, and an agent is
      # its engine's or its run's to stop. `stop --all` stops them too.
      OWNED = [RUN, AGENT].freeze

      # The stop signal per role; TERM for the rest. An engine or a run
      # takes INT as a deliberate quit and stops its agents; TERM would end
      # it and leave them running for an engine to reattach (B2 in plan 041).
      SIGNALS = { ENGINE => "INT", RUN => "INT" }.freeze

      # Longer waits, per role. A supervisor ends only once its children
      # have; an engine or a run gives its agents {Execution::Control::GRACE}
      # to write down where they got to.
      WAITS = { SUPERVISOR => Supervisor::GRACE + WAIT,
                ENGINE     => Execution::Control::GRACE + WAIT,
                RUN        => Execution::Control::GRACE + WAIT,
                AGENT      => Execution::AgentProcess::STOP_WITHIN }.freeze

      # @param dir [OpenLanes::Supervision::PidDir]
      # @param probe [OpenLanes::Supervision::Probe]
      # @param host [OpenLanes::Supervision::Host]
      # @param waits [Hash{String => Numeric}] seconds per role; {WAIT} for the rest
      def initialize(dir:, probe: Probe.new, host: Host::SYSTEM, waits: WAITS)
        @dir = dir
        @probe = probe
        @host = host
        @waits = waits
      end

      # The supervisor first, since it stops its children itself; then
      # whatever is still named: an engine or a web whose supervisor is gone,
      # and with +runs+ every `openlanes run` and every agent. The agents are
      # told `INTERRUPT` before anything else is stopped, and share one
      # {Execution::Control::GRACE} to leave their resume notes (C5 in plan
      # 041), as under a supervisor.
      #
      # @param runs [Boolean]
      # @param dry_run [Boolean]
      # @return [Array<Outcome>]
      def call(runs: false, dry_run: false)
        return stop_all if runs && !dry_run

        stop_named(dry_run:) { runs || !OWNED.include?(it) }
      end

      private

      # @param dry_run [Boolean]
      # @yieldparam role [String, nil] nil for an unreadable file
      # @yieldreturn [Boolean] whether to stop a process of that role
      # @return [Array<Outcome>]
      def stop_named(dry_run:)
        supervisors, rest = @dir.entries.partition { it.file&.role == SUPERVISOR }
        done = supervisors.map { stop(it, dry_run:) }
        # A supervisor's children remove their own files as it stops them.
        rest = @dir.entries unless dry_run
        done + rest.select { yield(it.file&.role) }.map { stop(it, dry_run:) }
      end

      # `stop --all`: the agents are told first, everything else is stopped,
      # and then the agents get what is left of the grace, TERM, and KILL.
      # Their files are removed as each ends; a KILLed one's is removed here.
      #
      # @return [Array<Outcome>]
      def stop_all
        sweep = AgentSweep.new(dir: @dir, probe: @probe, host: @host)
        deadline = @host.clock.monotonic + Execution::Control::GRACE
        sweep.interrupt
        done = stop_named(dry_run: false) { it != AGENT }
        done + swept(sweep, deadline) + @dir.entries.select { it.file&.role == AGENT }.map { stop(it, dry_run: false) }
      end

      # @param sweep [AgentSweep] already told to interrupt
      # @param deadline [Float] the monotonic time the grace runs out
      # @return [Array<Outcome>]
      def swept(sweep, deadline)
        sweep.call(grace: [deadline - @host.clock.monotonic, 0].max).map do |file, result|
          Outcome.new(file:, path: File.join(@dir.path, file.name), result:).tap { @dir.remove(file) }
        end
      end

      # @param entry [OpenLanes::Supervision::PidDir::Entry]
      # @param dry_run [Boolean]
      # @return [Outcome]
      def stop(entry, dry_run:)
        file = entry.file
        unless file && @probe.verified?(file)
          @dir.delete(entry.path) unless dry_run
          return Outcome.new(file:, path: entry.path, result: :stale)
        end
        return Outcome.new(file:, path: entry.path, result: :would_stop) if dry_run

        Outcome.new(file:, path: entry.path, result: terminate(file)).tap { @dir.delete(entry.path) }
      end

      # To the one process, never its group: a supervisor stops its own
      # children, and an engine's agents are its to stop. The role's stop
      # signal, then the same again, then KILL, each only to a process still there.
      #
      # @param file [OpenLanes::Supervision::PidFile]
      # @return [Symbol] :stopped or :killed
      def terminate(file)
        signal = SIGNALS.fetch(file.role, "TERM")
        [@waits.fetch(file.role, WAIT), HURRIED_WITHIN].each do |seconds|
          @host.signaller.call(signal, file.pid)
          return :stopped if gone_within?(file, seconds)
        end
        @host.signaller.call("KILL", file.pid)
        :killed
      end

      # @param file [OpenLanes::Supervision::PidFile]
      # @param seconds [Numeric]
      # @return [Boolean]
      def gone_within?(file, seconds)
        clock = @host.clock
        deadline = clock.monotonic + seconds
        clock.sleep(0.1) while @probe.verified?(file) && clock.monotonic < deadline
        !@probe.verified?(file)
      end
    end
  end
end
