# frozen_string_literal: true

module OpenLanes
  module Supervision
    # The agents' side of a whole-system stop (B3 and C2 in plan 041).
    # {#interrupt} sends USR1 to every agent of the project as the stop
    # begins, so each writes `INTERRUPT` into its control file and leaves a
    # resume note, the engine's or not. {#call} comes last: it waits out
    # what is left of the grace for them to end, TERMs those still there,
    # and KILLs with its CLI's group one that outlives its own stop. An
    # engine that quits stops its agents itself; this is for one that was
    # hung, KILLed, or had already crashed and left them.
    class AgentSweep
      # Seconds an agent supervisor gets after TERM: its own grace, TERM
      # then KILL to its CLI's group, and a margin.
      WITHIN = Execution::AgentProcess::STOP_WITHIN

      # Seconds between looks.
      POLL = 0.2

      # @param dir [OpenLanes::Supervision::PidDir]
      # @param probe [OpenLanes::Supervision::Probe]
      # @param host [OpenLanes::Supervision::Host]
      def initialize(dir:, probe: Probe.new, host: Host::SYSTEM)
        @dir = dir
        @probe = probe
        @host = host
        @told = []
      end

      # @return [Array<OpenLanes::Supervision::PidFile>] the agents it told
      def interrupt = (@told = agents).each { @host.signaller.call("USR1", it.pid) }

      # @param grace [Numeric] seconds the agents may still take to end on their own
      # @return [Hash{OpenLanes::Supervision::PidFile => Symbol}] each agent it
      #   told or found, :stopped or :killed
      def call(grace: 0)
        all = (@told + agents).uniq
        left = wait_out(all, grace)
        left.each { @host.signaller.call("TERM", it.pid) }
        late = wait_out(left, WITHIN).each { kill(it) }
        all.to_h { [it, late.include?(it) ? :killed : :stopped] }
      end

      private

      # @return [Array<OpenLanes::Supervision::PidFile>] every verified agent in the PID directory
      def agents = @dir.entries.filter_map { it.file if it.file&.role == AGENT }.select { @probe.verified?(it) }

      # @param agents [Array<OpenLanes::Supervision::PidFile>]
      # @param seconds [Numeric]
      # @return [Array<OpenLanes::Supervision::PidFile>] those still there at the deadline
      def wait_out(agents, seconds)
        clock = @host.clock
        deadline = clock.monotonic + seconds
        loop do
          late = agents.select { @probe.verified?(it) }
          return late if late.empty? || clock.monotonic >= deadline

          clock.sleep(POLL)
        end
      end

      # The CLI's group first, since KILL to the agent supervisor would
      # leave it running.
      #
      # @param file [OpenLanes::Supervision::PidFile]
      # @return [void]
      def kill(file)
        @host.signaller.call("KILL", -file.child) if file.child
        @host.signaller.call("KILL", file.pid)
      end
    end
  end
end
