# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OpenLanes
  module Slack
    # Slack's Web API, wrapped as thinly as {OpenLanes::Linear::API} wraps
    # Linear's, and for the same reason: it is a seam. Every example in the
    # suite injects a transport here, so nothing in the tests reaches Slack.
    #
    # Only the calls a poll needs are here: say who the token is, post a
    # message, change it, put a reaction on it, and read it back with its
    # thread. Everything is plain HTTPS the engine starts itself, so Slack
    # needs no URL to call back and the machine no open port.
    class API
      ENDPOINT = "https://slack.com/api"

      # The environment variable holding the bot token (`xoxb-…`).
      TOKEN_VARIABLE = "SLACK_BOT_TOKEN"

      # Seconds one call may take. The calls are made off the engine's loop,
      # but a hung one still holds every question behind it.
      TIMEOUT = 10

      # Slack said no, in its own word: `not_in_channel`, `invalid_auth`, …
      class Refused < Error
        # @return [String] Slack's error code
        attr_reader :code

        # @param method [String]
        # @param code [String]
        # @param needed [String, nil] the scope Slack says is missing
        def initialize(method, code, needed: nil)
          @code = code
          super("Slack refused #{method}: #{code}#{" (the app needs the #{needed} scope)" if needed}")
        end
      end

      # HTTP 429. Slack says how long to stay away.
      class RateLimited < Error
        # @return [Integer] seconds
        attr_reader :retry_after

        # @param retry_after [Integer]
        def initialize(retry_after)
          @retry_after = retry_after
          super("Slack asked for #{retry_after}s of quiet")
        end
      end

      # @param env [Hash] the environment
      # @return [String, nil] the token, nil when unset or blank
      def self.token_from(env = ENV) = env[TOKEN_VARIABLE].to_s.strip.then { it.empty? ? nil : it }

      # @param token [String, nil] a bot token
      # @param transport [#call, nil] `(method, params) -> Hash`, for tests
      # @param endpoint [String]
      def initialize(token: nil, transport: nil, endpoint: ENDPOINT)
        @token = token
        @transport = transport
        @endpoint = endpoint
        return if transport || (token && !token.empty?)

        raise Error, "no Slack token. Set #{TOKEN_VARIABLE} to the app's bot token (xoxb-…)"
      end

      # @return [Hash] `team`, `team_id`, `url`, `user_id`, `bot_id`
      def identity = call("auth.test")

      # @param channel [String] an id (`C0123`) or a public channel's `#name`
      # @param text [String] what a notification shows
      # @param blocks [Array<Hash>] Block Kit
      # @return [Hash] `channel` (always the id) and `ts`
      def post(channel:, text:, blocks:)
        call("chat.postMessage", channel:, text:, blocks: JSON.generate(blocks), unfurl_links: false)
      end

      # A reply in a message's thread.
      #
      # @param channel [String] the id
      # @param at [String] the `ts` of the message it replies to
      # @param text [String]
      # @return [Hash]
      def reply(channel:, at:, text:) = call("chat.postMessage", channel:, thread_ts: at, text:)

      # @param channel [String] the id
      # @param at [String] the message's `ts`, which is its id
      # @param text [String]
      # @param blocks [Array<Hash>]
      # @return [Hash]
      def update(channel:, at:, text:, blocks:) = call("chat.update", channel:, ts: at, text:, blocks: JSON.generate(blocks))

      # Adding one that is already there is success: a poll posted twice
      # over a crash must not fail on its second go.
      #
      # @param channel [String] the id
      # @param at [String] the message's `ts`, which is its id
      # @param name [String] the emoji, without colons
      # @return [void]
      def react(channel:, at:, name:)
        call("reactions.add", channel:, timestamp: at, name:)
      rescue Refused => e
        raise unless e.code == "already_reacted"
      end

      # A message and the replies in its thread, the message first.
      #
      # @param channel [String] the id
      # @param at [String] the message's `ts`, which is its id
      # @return [Array<Hash>]
      def thread(channel:, at:) = call("conversations.replies", channel:, ts: at, limit: 100).fetch("messages", [])

      # @param channel [String] the id
      # @param at [String] the message's `ts`, which is its id
      # @return [Array<Hash>] `{name, users}` per emoji on the message
      def reactions(channel:, at:)
        call("reactions.get", channel:, timestamp: at, full: true).dig("message", "reactions").to_a
      end

      # @param id [String] a user id
      # @return [Hash] the user, `real_name` among its fields
      def user(id) = call("users.info", user: id).fetch("user", {})

      private

      # Form-encoded, because Slack's read methods take nothing else; the
      # write methods take either, so one encoding serves all of them.
      #
      # @param method [String] e.g. "chat.postMessage"
      # @param params [Hash]
      # @return [Hash] the response, `ok` already checked
      def call(method, **params)
        data = @transport ? @transport.call(method, params) : request(method, params)
        return data if data["ok"]

        raise Refused.new(method, data["error"].to_s, needed: data["needed"])
      end

      # @return [Hash]
      def request(method, params)
        uri = URI("#{@endpoint}/#{method}")
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
          http.request(form(uri, params))
        end
        read(method, response)
      rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
        raise Error, "Slack did not answer #{method}: #{e.message.lines.first.to_s.strip}"
      end

      # @return [Net::HTTP::Post]
      def form(uri, params)
        Net::HTTP::Post.new(uri).tap do |post|
          post["Authorization"] = "Bearer #{@token}"
          post.set_form_data(params.transform_values(&:to_s))
        end
      end

      # @return [Hash]
      # @raise [RateLimited, OpenLanes::Error]
      def read(method, response)
        raise RateLimited, Integer(response["Retry-After"] || 30) if response.code == "429"
        raise Error, "Slack answered #{method} with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
