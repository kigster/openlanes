# frozen_string_literal: true

module OpenLanes
  module Execution
    # One agent, run through `openlanes-agent` (S6): the engine's side of
    # {AgentSupervisor}'s protocol. It answers {Child}'s interface, so the
    # executor reads an agent the way it always has, but what it reads is a
    # file the agent supervisor appends to, not a pipe that would end the
    # run with the engine.
    #
    #   spawn = AgentProcess.spawner(dir: trace_dir, root:)
    #   child = spawn.call(argv, chdir: worktree, label: AgentProcess::Label.new(plan: "005.00", agent: "backend-coder"))
    #   child.each_chunk { transcript.push(it) }
    #   child.wait.success?
    class AgentProcess
      # The agent supervisor, run without the gem.
      SCRIPT = File.expand_path("../../../libexec/openlanes-agent", __dir__)

      # Seconds between looks at the file while nothing new has arrived.
      POLL = 0.05

      # Seconds {#terminate} lets the agent supervisor finish its own stop,
      # TERM then KILL to the CLI's group, before it KILLs both itself.
      STOP_WITHIN = AgentSupervisor::TERM_GRACE + 5

      # Ended without a status: the agent supervisor itself was killed.
      LOST = ExitStatus.new(exitstatus: nil, termsig: 9)

      extend Registry

      class << self
        # The executor's spawn seam, for one project.
        #
        # @param dir [String] where the output and status files go
        # @param root [String] the project root, whose `tmp/pids` holds the PID file
        # @return [Starter]
        def spawner(dir:, root:) = Starter.new(dir:, root:)

        # An agent supervisor an earlier engine started, taken back from what
        # {#restart} recorded (B1 in plan 041). It is not this process's
        # child, so its end is read from its status file, or from its pid
        # being gone.
        #
        # @param fields [Hash{String => Object}] what {#restart} returned, keys as strings
        # @return [AgentProcess]
        def attach(fields)
          track(new(pid: Integer(fields.fetch("pid")),
            files: Files.new(output: fields.fetch("output"), status: fields.fetch("status"), pid_file: fields.fetch("pid_file"))))
        end
      end

      # @param pid [Integer] the agent supervisor's
      # @param files [Files]
      # @param stop_within [Numeric]
      def initialize(pid:, files:, stop_within: STOP_WITHIN)
        @pid = pid
        @files = files
        @stop_within = stop_within
        @ended = nil
        @abandoned = false
        @reaped = false
        @terminating = false
        @guard = Mutex.new
      end

      # @return [Integer] the agent supervisor's
      attr_reader :pid

      # What a restarted engine needs to {.attach} to it again.
      #
      # @return [Hash{Symbol => Object}]
      def restart = { pid:, **@files.to_h }

      # Read the output as it grows, until the agent has ended and every
      # byte it wrote has been read.
      #
      # @yieldparam text [String] whatever arrived, possibly a partial line
      # @return [void]
      def each_chunk
        File.open(@files.output, "rb") do |file|
          loop do
            chunk = file.read(65_536)
            next yield(chunk.force_encoding(Encoding::UTF_8)) if chunk
            break if ended?

            sleep(POLL)
          end
        end
      end

      # @return [ExitStatus]
      def wait
        return @ended if @ended

        sleep(POLL) until ended?
        reap
        @ended = ExitStatus.read(@files.status) || LOST
      ensure
        self.class.forget(self)
        FileUtils.rm_f([@files.output, @files.status])
      end

      # @return [Boolean] whether it has been waited for
      def finished? = !@ended.nil?

      # @return [Boolean]
      def alive?
        return false if @ended

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end

      # To the agent supervisor alone: it signals the CLI's group itself.
      #
      # @param signal [String]
      # @return [void]
      def kill(signal = "TERM")
        Process.kill(signal, pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      # TERM to the agent supervisor, which TERMs the CLI's group and KILLs
      # it after its grace. Should it not end within {STOP_WITHIN}, both are
      # KILLed from here and the reader let go. Once only.
      #
      # @return [void]
      def terminate
        return if @guard.synchronize { @terminating.tap { @terminating = true } }

        kill("TERM")
        deadline = monotonic + @stop_within
        sleep(POLL) until ended? || monotonic >= deadline
        return if ended?

        kill_cli
        kill("KILL")
        @abandoned = true
      end

      private

      # @return [Boolean] its status written, or nobody left to write it
      def ended? = @abandoned || File.exist?(@files.status) || gone?

      # A killed agent supervisor stays a zombie until it is reaped, and a
      # zombie still answers signal 0, so its parent asks `wait` instead.
      #
      # @return [Boolean]
      def gone?
        @reaped ||= !Process.wait2(pid, Process::WNOHANG).nil?
      rescue Errno::ECHILD
        # Reaped on another thread, or not this process's child at all.
        !alive?
      end

      # @return [void]
      def reap
        Process.wait(pid) unless @reaped
      rescue Errno::ECHILD
        nil
      end

      # @return [void]
      def kill_cli
        child = JSON.parse(File.read(@files.pid_file))["child"]
        Process.kill("KILL", -Integer(child))
      rescue SystemCallError, JSON::ParserError, TypeError, ArgumentError
        nil
      end

      # @return [Float]
      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
