# frozen_string_literal: true

module OpenLanes
  module Supervision
    # How the engine asks `openlanes start` to restart the control room
    # (plan 069.00, D1): it finds the supervisor's PID file, checks the
    # process is still the one that wrote it, and sends it {SIGNAL}. The
    # supervisor's trap only sets a flag; its next tick does the work.
    #
    # The supervisor writes its control room's URL into its PID file, so a
    # file with no URL is a `--no-web` start, which has nothing to restart.
    class RestartRequest
      # USR1 is taken: it tells agents to write down where they got to.
      SIGNAL = "USR2"

      # The reply when there is nobody to ask (D2).
      REFUSAL = "`/restart-web` needs `openlanes start`; no supervisor is running."

      # @param dir [OpenLanes::Supervision::PidDir]
      # @param probe [OpenLanes::Supervision::Probe]
      # @param host [OpenLanes::Supervision::Host]
      def initialize(dir:, probe: Probe.new, host: Host::SYSTEM)
        @dir = dir
        @probe = probe
        @host = host
      end

      # @return [Integer, nil] the supervisor's pid once signalled; nil when
      #   no supervisor with a control room is running, and nothing was sent
      def call
        file = @dir.read(SUPERVISOR)
        return unless file&.url && @probe.verified?(file)

        @host.signaller.call(SIGNAL, file.pid)
        file.pid
      end
    end
  end
end
