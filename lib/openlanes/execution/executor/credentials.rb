# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The API keys a project's environment can hand every agent by accident.
      module Credentials
        # Environment variables the `claude` CLI reads as credentials, in
        # preference to a claude.ai login.
        #
        # A project `.env` that sets one of these for the application's own use
        # reaches every agent a run spawns. `claude` then authenticates with that
        # key rather than the login, and a stale or unrelated one turns an entire
        # run into `401 API key is invalid`, three minutes per agent. The CLI warns
        # rather than unsets. Driving it with an API key on purpose is legitimate,
        # and nothing here can tell the two apart.
        VARS = %w[ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN].freeze

        # @param env [Hash]
        # @return [Array<String>] credential variables currently set
        def self.foreign(env) = VARS.reject { |name| env[name].to_s.strip.empty? }
      end
    end
  end
end
