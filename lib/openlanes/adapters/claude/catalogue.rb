# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OpenLanes
  module Adapters
    class Claude < Base
      # Every Claude model an agent may run on, read from Anthropic's Models
      # API and remembered on disk, with {Pricing::BUNDLED} as the fallback.
      #
      # There is no ceiling: the operator picks the model, and the page shows
      # every one Anthropic serves, newest first within a tier, priced by
      # {Pricing}.
      #
      # One fetch a day, at most: the list is kept in {#cache} for {TTL}, and
      # a fetch that fails falls back to whatever the cache holds, however
      # old, and then to the bundled list. A machine with no API credential
      # never fetches: the `claude` CLI's own login is not a credential this
      # class can borrow, so such a machine runs on the cache or the bundled
      # list, and {#source} says which.
      class Catalogue
        # Where the list comes from.
        URL = "https://api.anthropic.com/v1/models"

        # The API version header every request carries.
        API_VERSION = "2023-06-01"

        # How long a fetched list is trusted before it is fetched again.
        TTL = 24 * 60 * 60

        # Seconds to open the connection and to read the reply. A start-up
        # that waits on the network is a start-up nobody asked for.
        TIMEOUT = 5

        # Set to anything to never fetch: the suite sets it, so no spec
        # reaches the network whatever the developer's shell exports.
        OFFLINE_VARIABLE = "OPENLANES_MODELS_OFFLINE"

        # The credentials read, in order. An API key goes in `x-api-key`; an
        # OAuth token (what `ant auth print-credentials --access-token`
        # prints) goes in `Authorization: Bearer` with the beta header that
        # lets it through.
        API_KEY_VARIABLE = "ANTHROPIC_API_KEY"
        AUTH_TOKEN_VARIABLE = "ANTHROPIC_AUTH_TOKEN"
        OAUTH_BETA = "oauth-2025-04-20"

        # What a fetch can fail with; anything else is a bug and raises.
        FAILURES = [Error, SystemCallError, IOError, JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout,
                    OpenSSL::SSL::SSLError].freeze

        class << self
          # The list every {Claude} instance reads: built once per process,
          # on first use, so a run fetches at most once.
          #
          # @return [OpenLanes::Adapters::Claude::Catalogue]
          def current = @current ||= new

          # Forget the list, so the next {.current} builds it again.
          #
          # @return [void]
          def reset! = @current = nil

          # Where the fetched list is kept between runs.
          #
          # @return [String]
          def default_cache
            File.join(ENV.fetch("XDG_CACHE_HOME") { File.join(Dir.home, ".cache") }, "openlanes", "anthropic-models.json")
          end
        end

        # @param fetch [#call] takes a `Net::HTTP::Get`, returns a
        #   `Net::HTTPResponse`; the default performs it
        # @param cache [String] the file the fetched list is kept in
        # @param env [Hash{String => String}]
        # @param now [#call] returns the current `Time`
        def initialize(fetch: method(:perform), cache: self.class.default_cache, env: ENV, now: -> { Time.now })
          @fetch = fetch
          @cache = ModelCache.new(cache, now:)
          @env = env
        end

        # @return [String] the cache file
        def cache = @cache.path

        # Every model, most capable first and newest first within a tier.
        #
        # @return [Array<OpenLanes::Adapters::Model>]
        def models = (@models ||= load).first

        # Where {#models} came from, for the start-up box and the log:
        # "Anthropic (fetched just now)", "cache (2 hours old)",
        # "bundled list (no ANTHROPIC_API_KEY)".
        #
        # @return [String]
        def source = (@models ||= load).last

        # A full id as itself; an alias that is exactly a tier (`opus`) as the
        # newest model of that tier; no name as `sonnet`, the tier `claude`
        # runs unnamed. A full id the list lacks is priced as an estimate, so
        # a model that came out this morning still has a cost. Anything else,
        # `not-opus` or `sonnet-old` included, is no model at all.
        #
        # @param name [String, nil]
        # @return [OpenLanes::Adapters::Model, nil]
        def find(name)
          text = name.to_s
          text = Claude::UNNAMED if text.empty? || text == "default"
          return models.find { it.id.match?(/\Aclaude-#{text}-/) } if Pricing::TIERS.include?(text)

          models.find { it.id == text } || Pricing.estimate(text)
        end

        private

        # @return [Array(Array<OpenLanes::Adapters::Model>, String)] the list and its source
        def load
          cached, age = @cache.read
          credential = credential_headers
          return fallback(cached, age, offline_reason) if @env.key?(OFFLINE_VARIABLE) || credential.nil?
          return [cached, "cache (#{ModelCache.ago(age)})"] if cached && age < TTL

          fetched = fetch_all(credential)
          @cache.write(fetched)
          [fetched, "Anthropic (fetched just now)"]
        rescue *FAILURES => e
          UI.log("model list not fetched: #{e.message}", level: :warn)
          fallback(cached, age, "fetch failed")
        end

        # @return [String] why no fetch was attempted
        def offline_reason = @env.key?(OFFLINE_VARIABLE) ? "#{OFFLINE_VARIABLE} is set" : "no #{API_KEY_VARIABLE}"

        # The cache however old, else the shipped list, each saying why.
        #
        # @param cached [Array<OpenLanes::Adapters::Model>, nil]
        # @param age [Integer, nil]
        # @param why [String]
        # @return [Array(Array<OpenLanes::Adapters::Model>, String)]
        def fallback(cached, age, why)
          cached ? [cached, "cache (#{ModelCache.ago(age)}, #{why})"] : [Pricing::BUNDLED, "bundled list (#{why})"]
        end

        # @return [Hash{String => String}, nil] the headers that authenticate, nil without a credential
        def credential_headers
          key = @env[API_KEY_VARIABLE].to_s
          return { "x-api-key" => key } unless key.empty?

          token = @env[AUTH_TOKEN_VARIABLE].to_s
          return nil if token.empty?

          { "Authorization" => "Bearer #{token}", "anthropic-beta" => OAUTH_BETA }
        end

        # Every page of the list, then only Claude models, ordered.
        #
        # @param headers [Hash{String => String}]
        # @return [Array<OpenLanes::Adapters::Model>]
        def fetch_all(headers)
          models = pages(headers).flat_map { Array(it["data"]) }.filter_map { model_from(it) }
          raise Error, "Anthropic listed no Claude models" if models.empty?

          Pricing.sort(models)
        end

        # @param headers [Hash{String => String}]
        # @return [Array<Hash>] every page, in order
        def pages(headers)
          found = [fetch_page(headers, nil)]
          found << fetch_page(headers, found.last["last_id"]) while found.last["has_more"] && found.last["last_id"]
          found
        end

        # @param headers [Hash{String => String}]
        # @param after [String, nil] the `last_id` of the page before
        # @return [Hash] the decoded page
        def fetch_page(headers, after)
          uri = URI(URL)
          uri.query = URI.encode_www_form({ limit: 100, after_id: after }.compact)
          request = Net::HTTP::Get.new(uri)
          request["anthropic-version"] = API_VERSION
          request["accept"] = "application/json"
          headers.each { |k, v| request[k] = v }
          response = @fetch.call(request)
          raise Error, "Anthropic answered #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end

        # @param request [Net::HTTP::Get]
        # @return [Net::HTTPResponse]
        def perform(request)
          Net::HTTP.start(request.uri.host, request.uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
            http.request(request)
          end
        end

        # One row of the API as a model: the bundled rate when the gem knows
        # the id, the tier's rate as an estimate when it does not, and no
        # model at all for an id in no tier.
        #
        # @param row [Hash]
        # @return [OpenLanes::Adapters::Model, nil]
        def model_from(row)
          id = row["id"].to_s
          return nil unless id.start_with?("claude-")

          label = row["display_name"].to_s.delete_prefix("Claude ").strip.then { it.empty? ? Pricing.label_from(id) : it }
          context = row["max_input_tokens"]
          known = Pricing::BUNDLED.find { it.id == id }
          known ? known.with(label:, context: context || known.context) : Pricing.estimate(id, label:, context:)
        end
      end
    end
  end
end
