# frozen_string_literal: true

module OpenLanes
  module Supervision
    # The pipe that ties a child to its supervisor (S1). The supervisor keeps
    # the only write end; each child is handed the read end and watches it.
    # When the supervisor dies, however it dies, the kernel closes the write
    # end, the read returns end of file, and the child stops itself, so a
    # SIGKILLed supervisor never leaves a web without its engine.
    #
    #   lifeline = Lifeline.open                       # in the supervisor
    #   spawn(lifeline.env, *argv, **lifeline.options)
    #   Lifeline.watch                                 # in the child
    class Lifeline
      # Names the read end's descriptor in the child's environment.
      ENV_NAME = "OPENLANES_LIFELINE"

      # @return [OpenLanes::Supervision::Lifeline]
      def self.open = new(*IO.pipe)

      # Watches the descriptor the environment names, on a thread, and calls
      # +on_cut+ once it closes. The variable is removed first, so nothing
      # this process starts (an agent, a server) inherits the duty.
      #
      # @param env [Hash, ENV]
      # @param on_cut [#call] TERM to this process by default: the graceful stop
      # @return [Thread, nil] nil when this process has no supervisor
      def self.watch(env: ENV, on_cut: -> { ::Process.kill("TERM", ::Process.pid) })
        fd = env.delete(ENV_NAME) or return
        io = IO.for_fd(Integer(fd), autoclose: true)
        io.close_on_exec = true
        Thread.new do
          io.read
          on_cut.call
        end
      rescue ArgumentError, SystemCallError
        nil
      end

      # @param reader [IO]
      # @param writer [IO]
      def initialize(reader, writer)
        @reader = reader
        @writer = writer
      end

      # @return [Hash{String => String}] added to a child's environment
      def env = { ENV_NAME => @reader.fileno.to_s }

      # The read end, passed through at the same number. Every other
      # descriptor, the write end included, closes on exec as Ruby opens them.
      #
      # @return [Hash{IO => IO}] for `Process.spawn`
      def options = { @reader => @reader }

      # Closes both ends: every child watching sees end of file.
      #
      # @return [void]
      def cut
        [@writer, @reader].each { it.close unless it.closed? }
      end
    end
  end
end
