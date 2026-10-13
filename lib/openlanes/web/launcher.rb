# frozen_string_literal: true

require "net/http"
require "tmpdir"

module OpenLanes
  module Web
    # The API server beside a `openlanes run` (W7): `openlanes web` as a process
    # of its own, in its own process group, so a crash in one never takes the
    # other with it and stopping the run stops the server and nothing else.
    #
    #   web = Web.launcher(root:, plans_dir:, port: 11000, redis_url:).start
    #   web.ready?   # => true once /healthz answers
    #   web.stop
    class Launcher
      # The executable, from this gem rather than whatever is on PATH.
      EXE = File.join(GEM_ROOT, "exe", "openlanes")

      # Where the server finds this run's Redis. The URL can carry a password,
      # and argv is world-readable through `ps`; a child's environment is not.
      REDIS_URL_ENV = "OPENLANES_REDIS_URL"

      # Seconds {#start} waits for `/healthz`.
      READY_WITHIN = 10.0

      # Seconds {#stop} gives the server after TERM before KILL.
      STOP_WITHIN = 5.0

      # @param root [String] the checkout the run works in
      # @param plans_dir [String]
      # @param port [Integer]
      # @param redis_url [String]
      # @param log [String] where the server's output goes
      # @param ready_within [Float]
      # @param probe [Proc, nil] answers whether the server is up; `/healthz` by default
      def initialize(root:, plans_dir:, port:, redis_url:, log: default_log(root), ready_within: READY_WITHIN, probe: nil)
        @root = root
        @plans_dir = plans_dir
        @port = Integer(port)
        @redis_url = redis_url
        @log = log
        @ready_within = ready_within
        @probe = probe || method(:healthy?)
      end

      # @return [String]
      attr_reader :log

      # @return [Integer, nil]
      attr_reader :pid

      # @return [String]
      def url = "http://#{HOST}:#{@port}"

      # @return [Array<String>] what is spawned; the Redis URL is in {#env}, never here
      def argv
        [EXE, "web", "--port", @port.to_s, "--no-open", "--dir", @plans_dir]
      end

      # @return [Hash{String => String}] added to the server's environment
      def env = { REDIS_URL_ENV => @redis_url }

      # Spawn the server and wait for it to answer.
      #
      # @return [self]
      def start
        @pid = Process.spawn(env, *argv, chdir: @root, pgroup: true, in: File::NULL, %i[out err] => [@log, "a"])
        @ready = wait_until_ready
        self
      end

      # @return [Boolean] whether `/healthz` answered within the wait
      def ready? = @ready == true

      # TERM to the server's process group, then KILL if it lingers.
      #
      # @return [void]
      def stop
        return unless @pid

        signal("TERM")
        deadline = monotonic + STOP_WITHIN
        sleep 0.05 while alive? && monotonic < deadline
        signal("KILL") if alive?
        reap
        @pid = nil
      end

      private

      # @return [Boolean]
      def wait_until_ready
        deadline = monotonic + @ready_within
        until monotonic >= deadline
          return true if @probe.call
          return false unless alive?

          sleep 0.1
        end
        false
      end

      # @return [Boolean]
      def healthy?
        Net::HTTP.start(HOST, @port, open_timeout: 0.5, read_timeout: 1) { it.get("/healthz").code == "200" }
      rescue SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout
        false
      end

      # @return [Boolean]
      def alive?
        Process.waitpid(@pid, Process::WNOHANG).nil?
      rescue Errno::ECHILD
        false
      end

      # @return [void]
      def signal(name)
        Process.kill(name, -@pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      # Blocks: after KILL the child is gone or about to be, and a
      # non-blocking wait that runs before the kernel has finished with it
      # returns nil and leaves a zombie behind. ECHILD means {#alive?}
      # already reaped it.
      #
      # @return [void]
      def reap
        Process.waitpid(@pid)
      rescue Errno::ECHILD
        nil
      end

      # @return [Float]
      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # @return [String]
      def default_log(root) = File.join(Dir.tmpdir, "openlanes-web-#{File.basename(root)}.log")
    end
  end
end
