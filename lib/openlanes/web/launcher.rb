# frozen_string_literal: true

require "net/http"
require "socket"
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

      # Ports {#start} tries, from the one asked for, before giving up.
      PORTS_TRIED = 10

      # @param root [String] the checkout the run works in
      # @param plans_dir [String]
      # @param port [Integer]
      # @param redis_url [String]
      # @param log [String] where the server's raw STDOUT and STDERR go: a
      #   crash before its logger is up, and Puma's own complaints
      # @param logging [OpenLanes::Log::Settings, nil] where the server logs
      #   its requests; the engine's own, so both processes write one file
      # @param ready_within [Float]
      # @param probe [Proc, nil] answers whether the server is up; `/healthz` by default
      def initialize(root:, plans_dir:, port:, redis_url:, log: default_log(root), logging: Log.settings,
        ready_within: READY_WITHIN, probe: nil)
        @root = root
        @plans_dir = plans_dir
        @port = Integer(port)
        @redis_url = redis_url
        @log = log
        @logging = logging
        @ready_within = ready_within
        @probe = probe || method(:healthy?)
      end

      # @return [String]
      attr_reader :log

      # @return [Integer, nil]
      attr_reader :pid

      # @return [Integer] the port asked for, or the free one {#start} moved to
      attr_reader :port

      # @return [String]
      def url = "http://#{HOST}:#{@port}"

      # @return [Array<String>] what is spawned; the Redis URL is in {#env}, never here
      def argv
        [EXE, "web", "--port", @port.to_s, "--no-open", "--dir", @plans_dir]
      end

      # The Redis URL, and where to log. A server left to find its own log
      # would resolve `log/development.log` from its own root and defaults,
      # and a `--log` typed on `run` would move the engine's lines but not
      # the server's.
      #
      # @return [Hash{String => String}] added to the server's environment
      def env = { REDIS_URL_ENV => @redis_url, **@logging&.env.to_h }

      # Spawn the server on the first free port from the one asked for, and
      # wait for it to answer. A taken port is skipped before spawning, never
      # probed: a leftover `openlanes web` for another project answers
      # `/healthz` there, and the run once declared that server its own and
      # opened the browser on someone else's board.
      #
      # @return [self]
      def start
        free = free_port
        return taken unless free

        @port = free
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

      # @return [Integer, nil]
      def free_port = (@port...(@port + PORTS_TRIED)).find { free?(it) }

      # @param port [Integer]
      # @return [Boolean] whether nothing listens there
      def free?(port)
        TCPServer.new(HOST, port).close
        true
      rescue SystemCallError
        false
      end

      # Every port tried is taken: said in the log {#start}'s caller points at.
      #
      # @return [self]
      def taken
        File.write(@log, "Ports #{@port}-#{@port + PORTS_TRIED - 1} are all taken. Pass --port to use another.\n", mode: "a")
        @ready = false
        self
      end

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
      def default_log(root) = Engine::ProgressLog.default_path(root, kind: "web")
    end
  end
end
