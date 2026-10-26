# frozen_string_literal: true

module OpenLanes
  module Supervision
    # `openlanes start --background` (S4): starts the factory again, away
    # from the terminal, and waits for it to come up, so the command that
    # asked can print the control room's URL and return. Up means the
    # child's supervisor wrote its PID file and, unless it serves no page,
    # the page answers.
    #
    #   Supervision.detached(root:).call(argv:, env:, log:, web: true)
    #     # => Success(pid_file) or Failure(refusal)
    class Detached
      include Dry::Monads[:result]

      # Set for the child, which leaves the terminal's session.
      ENV_NAME = "OPENLANES_DETACHED"

      # Seconds it waits for the factory to come up.
      READY_WITHIN = 60

      # Seconds between looks.
      POLL = 0.2

      # Lines of the log quoted when the factory fails to start.
      TAIL = 20

      # In the child: leaves the session it was started in, so closing that
      # terminal sends it no SIGHUP. Its parent exits once the factory is up,
      # which leaves it to PID 1.
      #
      # @param env [Hash, ENV]
      # @return [void]
      def self.leave_session(env: ENV)
        ::Process.setsid if env.delete(ENV_NAME)
      rescue Errno::EPERM
        nil
      end

      # @param dir [OpenLanes::Supervision::PidDir] where the child's supervisor registers
      # @param host [OpenLanes::Supervision::Host]
      # @param answering [#call] port in, whether a page answers there
      def initialize(dir:, host: Host::SYSTEM, answering: OpenLanes::Web::Launcher.method(:answering?))
        @dir = dir
        @host = host
        @answering = answering
      end

      # @param argv [Array<String>] the command to start
      # @param env [Hash{String => String}] for it, which keeps secrets out of
      #   argv; {ENV_NAME} is added
      # @param log [String] where its output goes
      # @param web [Boolean] whether to wait for its page too
      # @return [Dry::Monads::Result] Success({PidFile}) once it is up, or
      #   Failure({Refusal}): 70 when it exited, 75 when it is still not up
      def call(argv:, env:, log:, web:)
        FileUtils.mkdir_p(File.dirname(log))
        pid = @host.spawner.spawn({ ENV_NAME => "1", **env }, *argv, in: File::NULL, %i[out err] => [log, "a"])
        wait(pid, log, web)
      end

      private

      # @param pid [Integer]
      # @param log [String]
      # @param web [Boolean]
      # @return [Dry::Monads::Result]
      def wait(pid, log, web)
        clock = @host.clock
        deadline = clock.monotonic + READY_WITHIN
        while clock.monotonic < deadline
          file = @dir.read(SUPERVISOR)
          return Success(file) if file&.pid == pid && (!web || answering?(file.url))
          return exited(log) if @host.waiter.call(pid)

          clock.sleep(POLL)
        end
        late(pid, log)
      end

      # @param url [String, nil]
      # @return [Boolean]
      def answering?(url) = !url.nil? && @answering.call(URI(url).port)

      # @param log [String]
      # @return [Dry::Monads::Result::Failure]
      def exited(log)
        tail = File.exist?(log) ? File.readlines(log).last(TAIL).join : ""
        Failure(Refusal.new(message: "The factory did not start. The end of #{log}:\n\n#{tail}", status: 70))
      end

      # @param pid [Integer]
      # @param log [String]
      # @return [Dry::Monads::Result::Failure]
      def late(pid, log)
        Failure(Refusal.new(message: "The factory (pid #{pid}) did not come up within #{READY_WITHIN}s. " \
                                     "It may still be starting: `openlanes status` shows it, #{log} says why.",
          status: 75))
      end
    end
  end
end
