# frozen_string_literal: true

require "net/http"
require "uri"

module OpenLanes
  module Apps
    # Whether the Preview tab may show an app in an iframe, or must open it in
    # a window of its own (M13, plan 012 item 11).
    #
    # The page cannot find out: a cross-origin frame's DOM is closed to it
    # and a refused frame still fires `load`. So the runner asks the app
    # itself, once its preview process is ready and after each restart, and
    # reads the two headers that refuse framing:
    #
    # - `X-Frame-Options`: `DENY` refuses everyone, and `SAMEORIGIN` refuses
    #   the control room too, whose origin differs from the app's by port.
    #   `ALLOW-FROM` is obsolete and ignored by browsers, so it frames.
    # - `Content-Security-Policy: frame-ancestors`: refuses unless one of its
    #   sources matches the control room's origin. `'self'` is the app's own
    #   origin, so it refuses too.
    #
    # Either one refusing sends the tab to a window. Browsers let
    # `frame-ancestors` override `X-Frame-Options`; this stays on the
    # cautious side, because a window always works and a refused frame is a
    # blank tab nobody can explain.
    module Framing
      # The control room's origin unless told otherwise.
      ORIGIN = "http://#{Status::HOST}:11000".freeze

      # Default ports, for a source that names none.
      DEFAULT_PORTS = { "http" => 80, "https" => 443 }.freeze

      module_function

      # @param headers [Hash{String => String, Array<String>}] any case
      # @param origin [String] the page that embeds it
      # @return [Symbol] `:frame` or `:window`
      def verdict(headers, origin: ORIGIN)
        values = headers.to_h { |name, value| [name.to_s.downcase, Array(value).join(",")] }
        refused = x_frame_refuses?(values["x-frame-options"]) || ancestors_refuse?(values["content-security-policy"], URI(origin))
        refused ? :window : :frame
      end

      # One GET of the URL the tab would open, then {.verdict}. An app that
      # cannot be asked opens in a window: it may work there, and an iframe
      # would show nothing either way.
      #
      # @param url [String]
      # @param origin [String]
      # @return [Symbol]
      def check(url, origin: ORIGIN)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = Probe::TIMEOUT
        http.read_timeout = Probe::TIMEOUT
        response = http.request_get(uri.request_uri)
        verdict(response.to_hash, origin:)
      rescue SystemCallError, IOError, Timeout::Error, Net::HTTPBadResponse, SocketError, URI::Error
        :window
      end

      # @param value [String, nil]
      # @return [Boolean]
      def x_frame_refuses?(value)
        value.to_s.split(",").map { it.strip.upcase }.intersect?(%w[DENY SAMEORIGIN])
      end

      # Every policy is enforced, so any one whose `frame-ancestors` leaves
      # the origin out refuses it. A policy without the directive allows
      # framing: it has no `default-src` fallback.
      #
      # @param value [String, nil] one or more policies, comma-joined
      # @param origin [URI::Generic]
      # @return [Boolean]
      def ancestors_refuse?(value, origin)
        value.to_s.split(",").any? do |policy|
          directive = policy.split(";").map(&:strip).find { it.downcase.start_with?("frame-ancestors") }
          directive && directive.split[1..].none? { allows?(it, origin) }
        end
      end

      # @param source [String] one source expression
      # @param origin [URI::Generic]
      # @return [Boolean]
      def allows?(source, origin)
        text = source.strip.downcase
        return true if text == "*"
        return text.delete_suffix(":") == origin.scheme if text.match?(/\A[a-z][a-z0-9+.-]*:\z/)
        return false if text.start_with?("'")

        host_allows?(text, origin)
      end

      # @return [Boolean]
      def host_allows?(text, origin)
        match = text.match(%r{\A(?:(?<scheme>[a-z][a-z0-9+.-]*)://)?(?<host>[^:/]+)(?::(?<port>\d+|\*))?(?:/.*)?\z})
        return false unless match
        return false if match[:scheme] && match[:scheme] != origin.scheme
        return false unless host_matches?(match[:host], origin.host)

        port = match[:port]
        port == "*" || (port || DEFAULT_PORTS[match[:scheme] || origin.scheme]).to_i == origin.port
      end

      # @return [Boolean]
      def host_matches?(pattern, host)
        return host == pattern unless pattern.start_with?("*.")

        host.end_with?(pattern.delete_prefix("*"))
      end
    end
  end
end
