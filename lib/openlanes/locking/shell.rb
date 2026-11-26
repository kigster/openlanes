# frozen_string_literal: true

require "json"
require "tty/command"

module OpenLanes
  module Locking
    # {Adapter} over the `alock` command: one fork and exec per call.
    #
    # Thread safety: one mutex serialises every call. The dispatcher's tick,
    # the agents' threads and the merge watcher all reach alock through the
    # one adapter, and a TTY::Command is not documented as safe to share, so
    # the adapter never lets two run at once. Each call is killed after
    # {TIMEOUT} seconds, so one hung `alock` cannot hold every other thread
    # behind the mutex. The holder goes in each call's own environment,
    # never in the process's, which another thread reads.
    #
    # Lifetime: alock pins a lock to the process that runs it, skipping
    # shells, which is this one, so every lock ends with openlanes.
    class Shell
      include Adapter

      # alock's exit code for "somebody else holds it" and "not locked".
      REFUSED = 1

      # Seconds one `alock` may take. It answers in well under one; a call
      # still running after this is stuck (a Redis backend that stopped
      # answering), and is killed and reported as a failure.
      #
      # tty-command counts the time the child spends silent, and resets it on
      # output, so a call that prints and then stalls can take up to twice
      # this. SIGKILL goes to the child only; alock is one process, since
      # the rbenv shim `exec`s it.
      TIMEOUT = 10

      # The command this adapter runs.
      EXECUTABLE = "alock"

      # @param command [TTY::Command]
      # @param timeout [Numeric] seconds, see {TIMEOUT}
      # @param executable [String] see {EXECUTABLE}; the spec swaps in a slow child
      def initialize(command: TTY::Command.new(printer: :null), timeout: TIMEOUT, executable: EXECUTABLE)
        @command = command
        @timeout = timeout
        @executable = executable
        @mutex = Mutex.new
      end

      # @param root [String]
      # @return [Array<Lock>]
      def list(root)
        out = serially { @command.run(@executable, "list", "--json", "--dir", root, timeout: @timeout).out }
        locks(JSON.parse(out))
      rescue TTY::Command::ExitError, JSON::ParserError, TTY::Command::TimeoutExceeded, SystemCallError => e
        raise Unreadable, reason(e)
      end

      # @return [Outcome]
      def acquire(scope, intent, dir:, as:) = change("acquire", scope, intent, dir:, as:)

      # @return [Outcome]
      def release(scope, dir:, as:) = change("release", scope, dir:, as:)

      private

      # @return [Outcome]
      def change(*, dir:, as:)
        result = serially { @command.run!(@executable, *, "--dir", dir, env: { "AGENT_ID" => as }, timeout: @timeout) }
        status = { 0 => :done, REFUSED => :refused }.fetch(result.exit_status, :failed)
        Outcome.new(status:, message: (result.err.to_s + result.out.to_s).lines.first.to_s.strip)
      rescue TTY::Command::TimeoutExceeded, SystemCallError => e
        Outcome.new(status: :failed, message: reason(e))
      end

      # @param listed [Object] `alock list --json`, parsed
      # @return [Array<Lock>] the active ones
      # @raise [Unreadable] when it is not a list of locks
      def locks(listed)
        raise Unreadable, "alock list --json is not a list of locks" unless listed.is_a?(Array) && listed.all?(Hash)

        listed.filter_map do |lock|
          next unless lock["status"] == "active"

          Lock.new(agent: lock["agent_id"].to_s, scope: lock["scope"].to_s, tree: lock["tree"].to_s, intent: lock["intent"])
        end
      end

      # Only a missing executable means alock is not installed. Any other
      # system error (a fork refused for want of memory or file handles) is
      # passing, and the caller treats it as one failed call, not as alock
      # being gone for the rest of the run.
      #
      # @return [Object] the block's value
      # @raise [Unavailable] when there is no `alock` to run
      def serially(&)
        @mutex.synchronize(&)
      rescue Errno::ENOENT => e
        raise Unavailable, "alock is not installed: #{e.message}"
      end

      # TTY::Command's message is the command line first; the reason is in
      # the stderr lines after it.
      #
      # @param error [Exception]
      # @return [String]
      def reason(error)
        return "#{@executable} timed out after #{@timeout}s" if error.is_a?(TTY::Command::TimeoutExceeded)

        lines = error.message.lines.map(&:strip).reject(&:empty?)
        lines.find { it.start_with?("stderr:") } || lines.first.to_s
      end
    end
  end
end
