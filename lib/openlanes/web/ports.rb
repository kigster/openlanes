# frozen_string_literal: true

require "socket"

module OpenLanes
  module Web
    # Finding a port nothing listens on, from the one asked for upward. A
    # development server on 11000 and a second checkout's `openlanes web`
    # used to collide there, and the second one refused to start.
    module Ports
      # Ports tried, from the one asked for, before giving up.
      TRIED = 10

      module_function

      # @param from [Integer, String] the port asked for
      # @param host [String]
      # @param tried [Integer]
      # @return [Integer, nil] the first free port, or nil when every one tried is taken
      def first_free(from, host: "127.0.0.1", tried: TRIED)
        start = Integer(from)
        (start...(start + tried)).find { free?(it, host:) }
      end

      # Binding is the only honest test: a probe by connecting misses a
      # server that is up but not answering yet.
      #
      # @param port [Integer]
      # @param host [String]
      # @return [Boolean] whether nothing listens there
      def free?(port, host: "127.0.0.1")
        TCPServer.new(host, port).close
        true
      rescue SystemCallError
        false
      end
    end
  end
end
