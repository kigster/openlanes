# frozen_string_literal: true

require "puma"
require "puma/log_writer"
require "puma/server"

module OpenLanes
  module Web
    # The app on Puma, multi-threaded because every open page holds one
    # thread for its event stream, and bound to {HOST} unless a {Listen}
    # names other addresses.
    #
    #   server = Web.server(app:, context:, port: 11000).start
    #   server.url   # => "http://127.0.0.1:11000"
    #   server.wait  # until #stop
    class Server
      # Threads: one per open event stream plus the requests beside them.
      MIN_THREADS = 2
      MAX_THREADS = 64

      # Seconds Puma waits for open streams after {#stop}. They notice the
      # context's `stopping` on the `stop` nudge {#stop} publishes; this is
      # the backstop, for a Redis that went away and took the nudge with it.
      SHUTDOWN_AFTER = 2

      # @param app [#call]
      # @param context [OpenLanes::Web::Context]
      # @param port [Integer] 0 for any free port
      # @param listen [OpenLanes::Web::Listen] the addresses to listen on
      # @param log [IO] where Puma writes its errors
      def initialize(app:, context:, port: DEFAULT_PORT, listen: Listen.parse(nil), log: $stderr)
        @app = app
        @context = context
        @port = Integer(port)
        @listen = listen
        @log = log
      end

      # @return [OpenLanes::Web::Listen]
      attr_reader :listen

      # Listen, and serve on Puma's own threads.
      #
      # @return [self]
      # @raise [Errno::EADDRINUSE] when the port is taken
      # @raise [Errno::EADDRNOTAVAIL] when an address is not this machine's
      def start
        @puma = Puma::Server.new(@app,
          nil,
          min_threads:          MIN_THREADS,
          max_threads:          MAX_THREADS,
          force_shutdown_after: SHUTDOWN_AFTER,
          log_writer:           Puma::LogWriter.new(File.open(File::NULL, "w"), @log))
        # Port 0 is resolved by the first listener, and the rest share it, so
        # every address answers on the one port {#url} reports.
        @listen.ips.each { @puma.add_tcp_listener(it, @puma.connected_ports.first || @port) }
        @thread = @puma.run
        @context.chat&.start
        self
      end

      # @return [Integer] the port listened on, the real one when 0 was asked
      def port = @puma&.connected_ports&.first || @port

      # @return [String] where this machine's browser opens the page
      def url = @listen.browse_url(port)

      # @return [Array<String>] every address the page answers on
      def urls = @listen.urls(port)

      # Block until the server stops.
      #
      # @return [void]
      def wait = @thread&.join

      # Stop listening, end every open stream, and wait for Puma.
      #
      # @return [void]
      def stop
        @context.stopping.make_true
        # Wakes every stream blocked waiting for news, here and on any other
        # server following this project, so ours see `stopping` now rather
        # than at their next ping. The others look, find nothing, and sleep.
        Live::News.publish(store: @context.store, keys: @context.keys, kind: "stop")
        @context.chat&.stop
        @puma&.stop(true)
        @context.stores.close
      end
    end
  end
end
