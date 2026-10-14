# frozen_string_literal: true

require "puma"
require "puma/log_writer"
require "puma/server"

module OpenLanes
  module Web
    # The app on Puma, multi-threaded because every open page holds one
    # thread for its event stream, and bound to {HOST} only.
    #
    #   server = Web.server(app:, context:, port: 11000).start
    #   server.url   # => "http://127.0.0.1:11000"
    #   server.wait  # until #stop
    class Server
      # Threads: one per open event stream plus the requests beside them.
      MIN_THREADS = 2
      MAX_THREADS = 64

      # Seconds Puma waits for open streams after {#stop}. They notice the
      # context's `stopping` within a tick; this is the backstop.
      SHUTDOWN_AFTER = 2

      # @param app [#call]
      # @param context [OpenLanes::Web::Context]
      # @param port [Integer] 0 for any free port
      # @param host [String]
      # @param log [IO] where Puma writes its errors
      def initialize(app:, context:, port: DEFAULT_PORT, host: HOST, log: $stderr)
        @app = app
        @context = context
        @port = Integer(port)
        @host = host
        @log = log
      end

      # @return [String]
      attr_reader :host

      # Listen, and serve on Puma's own threads.
      #
      # @return [self]
      # @raise [Errno::EADDRINUSE] when the port is taken
      def start
        @puma = Puma::Server.new(@app,
          nil,
          min_threads:          MIN_THREADS,
          max_threads:          MAX_THREADS,
          force_shutdown_after: SHUTDOWN_AFTER,
          log_writer:           Puma::LogWriter.new(File.open(File::NULL, "w"), @log))
        @puma.add_tcp_listener(@host, @port)
        @thread = @puma.run
        @context.chat&.start
        self
      end

      # @return [Integer] the port listened on, the real one when 0 was asked
      def port = @puma&.connected_ports&.first || @port

      # @return [String]
      def url = "http://#{@host}:#{port}"

      # Block until the server stops.
      #
      # @return [void]
      def wait = @thread&.join

      # Stop listening, end every open stream, and wait for Puma.
      #
      # @return [void]
      def stop
        @context.stopping.make_true
        @context.chat&.stop
        @puma&.stop(true)
        @context.stores.close
      end
    end
  end
end
