# frozen_string_literal: true

module OpenLanes
  module Supervision
    # `openlanes stop` (S2): TERM to each process a PID file names, a wait,
    # then KILL. Nothing is signalled before {Probe#verified?} says it is the
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

      # Seconds a process gets after the second TERM, which an engine or a
      # run takes as a second Ctrl-C: it KILLs its agents' groups and exits.
      HURRIED_WITHIN = Execution::Child::TERM_GRACE + 5

      # Longer waits, per role. A supervisor ends only once its children
      # have; an engine or a run gives its agents {Execution::Control::GRACE}
      # to write down where they got to.
      WAITS = { SUPERVISOR => Supervisor::GRACE + WAIT,
                ENGINE     => Execution::Control::GRACE + WAIT,
                RUN        => Execution::Control::GRACE + WAIT }.freeze

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
      # and with +runs+ every `openlanes run`.
      #
      # @param runs [Boolean]
      # @param dry_run [Boolean]
      # @return [Array<Outcome>]
      def call(runs: false, dry_run: false)
        supervisors, rest = @dir.entries.partition { it.file&.role == SUPERVISOR }
        done = supervisors.map { stop(it, dry_run:) }
        # A supervisor's children remove their own files as it stops them.
        rest = @dir.entries unless dry_run
        done + rest.select { runs || it.file&.role != RUN }.map { stop(it, dry_run:) }
      end

      private

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
      # children, and an engine's agents are its to stop. TERM, then a
      # second TERM, then KILL, each only to a process still there.
      #
      # @param file [OpenLanes::Supervision::PidFile]
      # @return [Symbol] :stopped or :killed
      def terminate(file)
        [["TERM", @waits.fetch(file.role, WAIT)], ["TERM", HURRIED_WITHIN]].each do |signal, seconds|
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
