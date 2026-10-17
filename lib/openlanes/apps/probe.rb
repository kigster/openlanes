# frozen_string_literal: true

require "net/http"
require "socket"

module OpenLanes
  module Apps
    # Whether a process is ready (plan 012, decision 1): something accepts a
    # TCP connection on its port, and, when its `ready:` names a path, a GET
    # of that path answers 2xx or 3xx.
    #
    # Only ever on the port the process was given. An app that moved to
    # another port (Vite without `--strictPort` does) therefore never
    # becomes ready, which is how a moved port fails the start rather than
    # leaving the Preview tab pointing at nothing.
    module Probe
      # Seconds a connect, and a read, may take.
      TIMEOUT = 1

      module_function

      # @param port [Integer]
      # @param path [String, nil]
      # @return [Boolean]
      def ready?(port, path: nil)
        return false unless listening?(port)
        return true if path.nil?

        status(port, path).between?(200, 399)
      end

      # Something accepted a connection on the port. Asking the socket for
      # its peer is the part that matters: behind a network filter (Little
      # Snitch on macOS) `Socket.tcp` with `connect_timeout` returns a socket
      # for a refused connect, and only `getpeername` then says EINVAL. Without
      # it every port on the machine reads as taken.
      #
      # @param port [Integer]
      # @param timeout [Numeric] seconds the connect may take
      # @return [Boolean]
      def listening?(port, timeout: TIMEOUT)
        Socket.tcp(Status::HOST, port, connect_timeout: timeout) do |socket|
          socket.remote_address
          true
        end
      rescue SystemCallError, IOError, SocketError
        false
      end

      # @param port [Integer]
      # @param path [String]
      # @return [Integer] the status, 0 when nothing answered
      def status(port, path)
        http = Net::HTTP.new(Status::HOST, port)
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT
        http.request_get(path).code.to_i
      rescue SystemCallError, IOError, Timeout::Error, Net::HTTPBadResponse, SocketError
        0
      end
    end
  end
end
