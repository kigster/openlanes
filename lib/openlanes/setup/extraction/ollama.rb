# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OpenLanes
  module Setup
    module Extraction
      # The person's Ollama server, when one answers.
      class Ollama
        # Where Ollama listens unless OLLAMA_HOST says otherwise.
        DEFAULT_HOST = "http://127.0.0.1:11434"

        # A server that does not answer in this long is not running.
        TIMEOUT = 1

        # @param host [String, nil] OLLAMA_HOST as Ollama itself reads it: the
        #   scheme is optional, and 0.0.0.0 is a bind address rather than one to dial
        # @param get [#call] takes a URI, answers with the body; the seam specs replace
        def initialize(host: nil, get: method(:fetch))
          @host = host.to_s.strip.empty? ? DEFAULT_HOST : host.strip
          @get = get
        end

        # @return [Array<String>] the models pulled; empty when nothing answers
        def models
          JSON.parse(@get.call(URI("#{base}/api/tags"))).fetch("models", []).filter_map { it["name"] }
        rescue SystemCallError, IOError, SocketError, Timeout::Error, JSON::ParserError, URI::Error
          []
        end

        # @return [String] its OpenAI-compatible endpoint
        def chat_url = "#{base}/v1/chat/completions"

        private

        # @return [String]
        def base
          url = @host.match?(%r{\A\w+://}) ? @host : "http://#{@host}"
          url.sub("0.0.0.0", "127.0.0.1").delete_suffix("/")
        end

        # @param uri [URI::HTTP]
        # @return [String]
        def fetch(uri)
          Net::HTTP.start(uri.host, uri.port, open_timeout: TIMEOUT, read_timeout: TIMEOUT) { it.get(uri.path).body }
        end
      end
    end
  end
end
