# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What the dispatcher holds on a running invocation, so a keypress can
      # reach it: the process, its clock and its control file.
      #
      # Filled in by {#call} once the child exists. Every method tolerates the
      # gap before that, because the keyboard does not wait.
      class Handle
        include Stopping
        include Compacting
        include Timekeeping

        def initialize
          @mutex = Mutex.new
          @requested = nil
          @compaction = nil
          @closed = false
        end

        # @return [OpenLanes::Execution::AgentProcess, nil] the process running now,
        #   which after a compaction is no longer the first one
        attr_accessor :child

        # @return [String, nil] the CLI's session id, once its stream named it
        attr_accessor :session

        # @return [OpenLanes::Execution::AgentProcess::Label, nil] which agent,
        #   on which plan, for the agent supervisor's files and title
        attr_accessor :label

        # @return [String, nil] the raw NDJSON trace the agent's stream is
        #   copied into, so the engine journal can name it and its offset
        attr_accessor :trace

        # @return [#call, nil] told, as a Hash, each part of what a restarted
        #   engine needs to take this invocation back (B5 in plan 041),
        #   whenever that part changes
        attr_accessor :on_restart

        # @return [String, nil] why the invocation was given up on while its
        #   provider was rate limiting it or overloaded, once it was
        attr_accessor :throttled

        # @param fields [Hash{Symbol => Object}]
        # @return [void]
        def restart!(**fields) = on_restart&.call(fields)

        # @return [Integer, nil]
        def pid = child&.pid
      end
    end
  end
end
