# frozen_string_literal: true

require "rack/body_proxy"
require "rack/utils"

module OpenLanes
  module Web
    # One log entry per request, through {Log}, wrapped around the whole app
    # so a request Rack::Protection or host authorization turns away is
    # logged too.
    #
    # Not Sinatra's `logging` or Rack::CommonLogger: both write Apache-style
    # text to `rack.errors`, which is the launcher's raw output file rather
    # than the log the engine writes, and neither knows a page from a request.
    #
    # The event stream is the exception to "one entry per request". It stays
    # open as long as the page does, so it is logged twice: when it opens, and
    # when Puma closes its body, with how long it was open. Logged once, at
    # the end, a page left open all day would not appear until evening.
    #
    # Static assets and `/healthz` are logged at debug: the launcher polls
    # `/healthz` ten times a second while it waits, and a page load fetches a
    # dozen assets, so at info they would bury the API calls.
    class RequestLog
      # A response of this type is a stream that outlives its request.
      STREAM = "text/event-stream"

      # Paths logged at info. Everything else is the page's own files.
      API = %r{\A/api(/|\z)}

      # @param app [#call]
      # @param logger [#info, #debug, #error, nil] {Log.logger} when nil, read
      #   per request so a {Log.setup} after this was built still applies
      # @param clock [#call] monotonic seconds
      def initialize(app, logger: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @app = app
        @logger = logger
        @clock = clock
      end

      # @param env [Hash] the Rack environment
      # @return [Array] status, headers and body, the body wrapped for a stream
      def call(env)
        started = @clock.call
        status, headers, body = @app.call(env)
        return [status, headers, opened(env, status, started, body)] if stream?(headers)

        write(level(env), env, "#{line(env)} #{status}", status:, started:)
        [status, headers, body]
      rescue StandardError => e
        write(:error, env, "#{line(env)} raised #{e.class}", status: 500, started:, exception: e)
        raise
      end

      private

      # Logs the stream opening, and hands back a body that logs its close.
      #
      # @return [Rack::BodyProxy]
      def opened(env, status, started, body)
        write(:info, env, "#{line(env)} stream opened", status:)
        Rack::BodyProxy.new(body) { write(:info, env, "#{line(env)} stream closed", status:, started:) }
      end

      # @param headers [Hash]
      # @return [Boolean]
      def stream?(headers)
        type = headers["content-type"] || headers["Content-Type"]
        type.to_s.start_with?(STREAM)
      end

      # @param env [Hash]
      # @return [Symbol]
      def level(env) = env["PATH_INFO"].to_s.match?(API) ? :info : :debug

      # @param env [Hash]
      # @return [String] e.g. "GET /api/board"
      def line(env) = "#{env["REQUEST_METHOD"]} #{env["PATH_INFO"]}"

      # The page's own id, from `?page=`, so the requests one browser tab
      # made can be picked out of several tabs' worth.
      #
      # @param env [Hash]
      # @return [String, nil]
      def page(env)
        id = Rack::Utils.parse_query(env["QUERY_STRING"].to_s)["page"]
        id.is_a?(String) && !id.empty? ? id : nil
      end

      # @param level [Symbol]
      # @param env [Hash]
      # @param message [String]
      # @param status [Integer]
      # @param started [Float, nil] when given, the entry carries the duration since
      # @param exception [Exception, nil]
      # @return [void]
      def write(level, env, message, status:, started: nil, exception: nil)
        payload = { method: env["REQUEST_METHOD"], path: env["PATH_INFO"], status: status.to_i, page: page(env) }.compact
        entry = { message:, payload:, exception: }.compact
        entry[:duration] = ((@clock.call - started) * 1000).round(1) if started
        (@logger || Log.logger).public_send(level, **entry)
      rescue StandardError
        # A log that cannot be written is no reason to fail the request.
        nil
      end
    end
  end
end
