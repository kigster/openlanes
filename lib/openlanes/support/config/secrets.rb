# frozen_string_literal: true

require "uri"

module OpenLanes
  class Config
    # The project file is committed with the project, so a secret written
    # into it is a secret published. Parsing refuses one rather than reading
    # it: a `redis_url` that carries a password, a value holding a known
    # token or a URL with a password in it, or a non-empty value under a key
    # named like a credential.
    #
    # Every check runs on every string at every depth. The first version
    # looked for a password in the top-level `redis_url` only and for a token
    # at the start of a value only, so `commands.run.redis_url`, a token used
    # as a Redis user name and `CODECOV_TOKEN=… rspec` were all committed and
    # pushed by the settings page.
    module Secrets
      # A token anywhere in a value. The shapes are {Memory::Secrets}'s, which
      # ask for a realistic length after the prefix: a bare `sk-` prefix
      # refused `project: sk-8 ski club`.
      TOKEN = Regexp.union(Memory::Secrets::VENDOR.values)

      # A URL with a password in its userinfo, anywhere in a value: a
      # command line such as `DATABASE_URL=postgres://app:pw@db rails s`.
      CREDENTIAL_URL = Memory::Secrets::CREDENTIAL_URL

      # Redis also takes its password as a query parameter.
      QUERY_PASSWORD = /[?&]password=[^&#\s]/i

      # The key a Redis URL sits under, at the top level and under each
      # command in `commands:`.
      REDIS_KEY = "redis_url"

      # Key names that hold a credential whatever their value looks like:
      # the whole name, or its last underscore-separated word. Anchored,
      # because a substring match refused `max_tokens: "200k"` as a secret.
      KEY = /(?:\A|_)(?:token|secret|password|passwd|api_?key)\z/i

      module_function

      # @param settings [Hash] the parsed file, string keys
      # @param path [String] for the message
      # @return [void]
      # @raise [OpenLanes::Error] at the first secret found
      def refuse!(settings, path)
        walk(settings, []) do |keys, value|
          found = finding(keys, value)
          raise Error, "#{path}: #{keys.join(".")} #{found}" if found
        end
      end

      # @param keys [Array<String>] the key path to the value
      # @param value [String]
      # @return [String, nil] what is wrong with the value and where it
      #   belongs instead, nil when it may be committed
      def finding(keys, value)
        if keys.last == REDIS_KEY && password?(value)
          "carries a password; this file is committed, so set the REDIS_URL environment variable instead"
        elsif secret?(keys, value)
          "looks like a secret; this file is committed, so put it in an environment variable instead"
        end
      end

      # @param url [String] a Redis URL
      # @return [Boolean] whether it names a password, in its userinfo or as `?password=`
      def password?(url)
        return true if url.match?(QUERY_PASSWORD)

        userinfo = URI.parse(url.strip).userinfo
        !userinfo.nil? && userinfo.include?(":") && !userinfo.split(":", 2).last.empty?
      rescue URI::Error
        url.match?(%r{\A\s*[a-z]+://[^/@]*:[^/@]+@})
      end

      # Yields every string value, with the key path to it.
      #
      # @param node [Object]
      # @param keys [Array<String>]
      # @yieldparam keys [Array<String>]
      # @yieldparam value [String]
      # @return [void]
      def walk(node, keys, &)
        case node
        when Hash
          node.each { |key, value| walk(value, [*keys, key.to_s], &) }
        when Array
          node.each_with_index { |value, index| walk(value, [*keys, index.to_s], &) }
        when String
          yield(keys, node)
        end
      end

      # @param keys [Array<String>]
      # @param value [String]
      # @return [Boolean]
      def secret?(keys, value)
        return false if value.strip.empty?
        return true if value.match?(TOKEN) || value.match?(CREDENTIAL_URL)

        keys.last.to_s.match?(KEY)
      end
    end
  end
end
