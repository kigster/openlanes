# frozen_string_literal: true

module OpenLanes
  # The one place a child process is started, so a spec can start none.
  #
  # Named `Spawner`, not `Process`: Zeitwerk would resolve an
  # `OpenLanes::Process` ahead of `::Process` at every bare `Process.kill`
  # and `Process.wait` under `lib/openlanes`.
  module Spawner
    # Starts real processes.
    module System
      module_function

      # @param env [Hash{String => String}]
      # @param argv [Array<String>]
      # @param options [Hash] as `Process.spawn` takes them
      # @return [Integer] the pid
      def spawn(env, *argv, **) = ::Process.spawn(env, *argv, **)
    end

    # Records what would have been started and hands back scripted pids.
    class Fake
      # One recorded call.
      Call = Data.define(:env, :argv, :options)

      # @return [Array<Call>]
      def calls = @mutex.synchronize { @calls.dup }

      # @param pids [Array<Integer>] handed out in order; a counter from
      #   `first_pid` once they run out
      # @param first_pid [Integer]
      def initialize(pids: [], first_pid: 90_000)
        @pids = pids.dup
        @next = first_pid
        @calls = []
        @mutex = Mutex.new
      end

      # @param env [Hash{String => String}]
      # @param argv [Array<String>]
      # @param options [Hash]
      # @return [Integer]
      def spawn(env, *argv, **options)
        @mutex.synchronize do
          @calls << Call.new(env:, argv:, options:)
          @pids.shift || (@next += 1)
        end
      end
    end
  end
end
