# frozen_string_literal: true

require "uri"

module OpenLanes
  class Config
    # The project file is committed with the project, so a secret written
    # into it is a secret published. Parsing refuses one rather than reading
    # it: a `redis_url` that carries a password, a value shaped like a known
    # token, or a non-empty value under a key named like a credential.
    module Secrets
      # Prefixes real credentials carry: GitHub, OpenAI and Anthropic, Slack,
      # Linear, AWS access keys.
      TOKEN = /\A(?:gh[pousr]_|github_pat_|sk-|xox[abpr]-|lin_api_|AKIA[0-9A-Z]{12})/

      # Key names that hold a credential whatever their value looks like.
      KEY = /token|secret|password|passwd|api_?key/i

      module_function

      # @param settings [Hash] the parsed file, string keys
      # @param path [String] for the message
      # @return [void]
      # @raise [OpenLanes::Error] at the first secret found
      def refuse!(settings, path)
        refuse_redis!(settings["redis_url"], path)
        walk(settings, []) do |keys, _value|
          raise Error,
            "#{path}: #{keys.join(".")} looks like a secret; this file is committed, " \
            "so put it in an environment variable instead"
        end
      end

      # @param value [Object]
      # @param path [String]
      # @return [void]
      def refuse_redis!(value, path)
        return unless value.is_a?(String) && password?(value)

        raise Error,
          "#{path}: redis_url carries a password; this file is committed, " \
          "so set the REDIS_URL environment variable instead"
      end

      # @param url [String]
      # @return [Boolean]
      def password?(url)
        userinfo = URI.parse(url.strip).userinfo
        !userinfo.nil? && userinfo.include?(":") && !userinfo.split(":", 2).last.empty?
      rescue URI::Error
        url.match?(%r{\A[a-z]+://[^/@]*:[^/@]+@})
      end

      # Yields each string value that is a secret, with the key path to it.
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
          yield(keys, node) if secret?(keys, node)
        end
      end

      # @param keys [Array<String>]
      # @param value [String]
      # @return [Boolean]
      def secret?(keys, value)
        return false if value.strip.empty? || keys.first == "redis_url"
        return true if value.strip.match?(TOKEN)

        keys.last.to_s.match?(KEY)
      end
    end
  end
end
