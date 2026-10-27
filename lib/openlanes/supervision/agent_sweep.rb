# frozen_string_literal: true

module OpenLanes
  module Supervision
    # The last step of a whole-system stop (B3 in plan 041): every agent of
    # the project still alive once the engine is down is TERMed, all at once,
    # and KILLed with its CLI's group should it outlive its own stop. An
    # engine that quits stops its agents itself; this is for the one that
    # was hung, KILLed, or had already crashed and left them.
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
      end

      # @return [Array<OpenLanes::Supervision::PidFile>] the agents it stopped
      def call
        agents = @dir.entries.filter_map { it.file if it.file&.role == AGENT }.select { @probe.verified?(it) }
        agents.each { @host.signaller.call("TERM", it.pid) }
        late = wait_out(agents)
        late.each { kill(it) }
        agents
      end

      private

      # @param agents [Array<OpenLanes::Supervision::PidFile>]
      # @return [Array<OpenLanes::Supervision::PidFile>] those still there at the deadline
      def wait_out(agents)
        clock = @host.clock
        deadline = clock.monotonic + WITHIN
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
