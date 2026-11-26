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
    # the adapter never lets two run at once. The holder goes in each call's
    # own environment, never in the process's, which another thread reads.
    class Shell
      include Adapter

      # alock's exit code for "somebody else holds it" and "not locked".
      REFUSED = 1

      # @param command [TTY::Command]
      def initialize(command: TTY::Command.new(printer: :null))
        @command = command
        @mutex = Mutex.new
      end

      # @param root [String]
      # @return [Array<Lock>]
      def list(root)
        out = serially { @command.run("alock", "list", "--json", "--dir", root).out }
        JSON.parse(out).filter_map do |lock|
          next unless lock["status"] == "active"

          Lock.new(agent: lock["agent_id"].to_s, scope: lock["scope"].to_s, tree: lock["tree"].to_s, intent: lock["intent"])
        end
      rescue TTY::Command::ExitError, JSON::ParserError => e
        raise Unreadable, reason(e)
      end

      # @return [Outcome]
      def acquire(scope, intent, dir:, as:) = change("acquire", scope, intent, dir:, as:)

      # @return [Outcome]
      def release(scope, dir:, as:) = change("release", scope, dir:, as:)

      private

      # @return [Outcome]
      def change(*, dir:, as:)
        result = serially { @command.run!("alock", *, "--dir", dir, env: { "AGENT_ID" => as }) }
        status = { 0 => :done, REFUSED => :refused }.fetch(result.exit_status, :failed)
        Outcome.new(status:, message: (result.err.to_s + result.out.to_s).lines.first.to_s.strip)
      end

      # @return [Object] the block's value
      # @raise [Unavailable] when there is no `alock` to run
      def serially(&)
        @mutex.synchronize(&)
      rescue SystemCallError => e
        raise Unavailable, "alock is not installed: #{e.message}"
      end

      # TTY::Command's message is the command line first; the reason is in
      # the stderr lines after it.
      #
      # @param error [Exception]
      # @return [String]
      def reason(error)
        lines = error.message.lines.map(&:strip).reject(&:empty?)
        lines.find { it.start_with?("stderr:") } || lines.first.to_s
      end
    end
  end
end
