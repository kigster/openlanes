# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"

module OpenLanes
  module Execution
    # `openlanes-agent` (S6): the small process between the engine and one
    # agent CLI, so the agent outlives an engine that dies or is restarted.
    # A pipe to the engine would end the run with it, so the CLI's output
    # goes to a file the engine follows, and its exit status to a second
    # file beside it.
    #
    # It runs as `ruby --disable-gems libexec/openlanes-agent`, so this file
    # uses the standard library only: no Bundler, no Zeitwerk, and nothing
    # else from the gem. The engine knows it only through its protocol, argv
    # in, files out and signals in, so a native build could replace it.
    #
    # @example
    #   openlanes-agent --root /work/app --plan 005.00 --agent backend-coder \
    #     --output /tmp/t/agent.out --status /tmp/t/agent.status \
    #     --pid-file /work/app/tmp/pids/agent-005.00-backend-coder.pid -- claude -p ...
    class AgentSupervisor
      # The PID file's role, and the first word of the title.
      ROLE = "agent"

      # Seconds between TERM and KILL to the CLI's group, as
      # {Execution::Child::TERM_GRACE}; a spec keeps the two equal.
      TERM_GRACE = 5

      # Seconds between looks at the CLI while it runs.
      POLL = 0.05

      # Exit status for a CLI that could not be started, as a shell has it.
      NOT_STARTED = 127

      # The flags it takes, each one required.
      FLAGS = %i[root plan agent output status pid_file].freeze

      # What it was started with.
      Options = Data.define(*FLAGS, :argv)

      # @param argv [Array<String>] its own arguments
      # @param title [#call] `Process.setproctitle` outside the suite
      # @return [Integer] the exit status to end with
      def self.main(argv, title: ::Process.method(:setproctitle))
        new(parse(argv), title:).call
      rescue OptionParser::ParseError, KeyError => e
        warn("openlanes-agent: #{e.message}")
        64
      end

      # @param argv [Array<String>]
      # @return [Options]
      # @raise [OptionParser::ParseError, KeyError] on a missing or unknown flag
      def self.parse(argv)
        given = {}
        rest = OptionParser.new do |o|
          FLAGS.each { |key| o.on("--#{key.to_s.tr("_", "-")} VALUE") { given[key] = it } }
        end.parse(argv)
        raise KeyError, "no command after --" if rest.empty?

        Options.new(**FLAGS.to_h { [it, given.fetch(it)] }, argv: rest)
      end

      # @param options [Options]
      # @param title [#call]
      # @param grace [Numeric] seconds between TERM and KILL
      def initialize(options, title: ::Process.method(:setproctitle), grace: TERM_GRACE)
        @options = options
        @title = title
        @grace = grace
        @stop_at = nil
        @termed = false
        @killed = false
      end

      # @return [Integer] the CLI's exit status, or 128 plus its signal
      def call
        @title.call("openlanes-#{ROLE} [#{File.basename(@options.root)}] #{@options.plan} #{@options.agent}")
        previous = trap_term
        pid = start or return finish(nil)
        write_pid_file(pid)
        finish(watch(pid))
      ensure
        trap("TERM", previous) if previous
        FileUtils.rm_f(@options.pid_file)
      end

      private

      # The CLI leads a process group of its own, so TERM and KILL reach
      # every tool it started, and its output goes to the file.
      #
      # @return [Integer, nil] nil when it could not be started
      def start
        FileUtils.mkdir_p(File.dirname(@options.output))
        ::Process.spawn(*@options.argv, in: File::NULL, out: [@options.output, "a"], err: %i[child out], pgroup: true)
      rescue SystemCallError => e
        File.write(@options.output, "openlanes-agent: could not start #{@options.argv.first}: #{e.message}\n", mode: "a")
        nil
      end

      # A trap may not take a lock, so it only notes the time; {#watch}
      # does the signalling. The handler it replaces is put back once the
      # CLI has ended, so a process that runs {#call} in-process (the
      # suite) is left as it was found.
      #
      # @return [Object] the previous handler
      def trap_term
        trap("TERM") { @stop_at = monotonic if @stop_at.nil? }
      end

      # @param pid [Integer]
      # @return [Process::Status]
      def watch(pid)
        loop do
          _, status = ::Process.wait2(pid, ::Process::WNOHANG)
          return status.tap { group("KILL", pid) } if status

          stop(pid) if @stop_at
          sleep(POLL)
        end
      end

      # TERM to the group once, KILL once the grace has run out.
      #
      # @param pid [Integer]
      # @return [void]
      def stop(pid)
        group("TERM", pid) unless @termed
        @termed = true
        return if @killed || monotonic - @stop_at < @grace

        group("KILL", pid)
        @killed = true
      end

      # A tool the CLI started can outlive it; whatever is left in the group
      # once the CLI ends is KILLed with it.
      #
      # @param signal [String]
      # @param pid [Integer]
      # @return [void]
      def group(signal, pid)
        ::Process.kill(signal, -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      # @param status [Process::Status, nil] nil when the CLI never started
      # @return [Integer]
      def finish(status)
        ended = if status.nil? then { exitstatus: NOT_STARTED }
                elsif status.signaled? then { termsig: status.termsig }
                else { exitstatus: status.exitstatus }
                end
        write_atomically(@options.status, JSON.generate(ended))
        ended[:exitstatus] || (128 + ended[:termsig])
      end

      # The same JSON as every other PID file, so `openlanes status` lists it
      # and {Supervision::Probe} verifies it.
      #
      # @param pid [Integer] the CLI's
      # @return [void]
      def write_pid_file(pid)
        file = { role: ROLE, pid: ::Process.pid, started:, root: @options.root, plans: [@options.plan],
                 agent: @options.agent, child: pid, output: @options.output, status: @options.status }
        write_atomically(@options.pid_file, JSON.pretty_generate(file.compact))
      end

      # @return [String, nil] this process's start time, as `ps` gives it
      def started
        out, status = Open3.capture2({ "LC_ALL" => "C" }, "ps", "-o", "lstart=", "-p", ::Process.pid.to_s)
        status.success? ? out.strip : nil
      rescue SystemCallError
        nil
      end

      # @param path [String]
      # @param text [String]
      # @return [void]
      def write_atomically(path, text)
        FileUtils.mkdir_p(File.dirname(path))
        File.write("#{path}.tmp", text)
        File.rename("#{path}.tmp", path)
      end

      # @return [Float]
      def monotonic = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end
  end
end
