# frozen_string_literal: true

module OpenLanes
  module Slack
    # Which channel, which workspace and who may answer: `slack:` in
    # `.openlanes/config.yml`, with the environment over it.
    #
    # The environment is read because the token already lives there. A
    # project whose `.env` holds `SLACK_BOT_TOKEN` can name its channel
    # beside it, and the Slack app that takes commands for the same engine
    # reads the same names, so the two never disagree on who is an operator.
    Settings = Data.define(:channel, :workspace, :operators, :interval) do
      # @!attribute [r] channel
      #   @return [String, nil]
      # @!attribute [r] workspace
      #   @return [String, nil]
      # @!attribute [r] operators
      #   @return [Array<String>] Slack user ids; empty when nobody is named
      # @!attribute [r] interval
      #   @return [Numeric] seconds between two calls to Slack

      # @return [Boolean]
      def operators? = operators.any?

      # Whether the project asked for Slack: a channel, a workspace or an
      # operator is named. The token does not count, because a token
      # exported for another tool would then make every project on the
      # machine warn on every run.
      #
      # @return [Boolean]
      def asked_for? = !channel.nil? || !workspace.nil? || operators?
    end

    class Settings
      CHANNEL = "OPENLANES_SLACK_CHANNEL"
      WORKSPACE = "OPENLANES_SLACK_WORKSPACE"
      # Ids separated by commas or spaces.
      OPERATORS = "OPENLANES_SLACK_OPERATORS"

      # A Slack user id, as the config schema's pattern for `operators` has it.
      USER_ID = /\A[UW][A-Z0-9]+\z/

      class << self
        # @param config [OpenLanes::Config]
        # @param env [Hash] the environment
        # @return [OpenLanes::Slack::Settings]
        # @raise [OpenLanes::Error] when {OPERATORS} names something that is
        #   not a user id: a name nobody's reaction could match would leave
        #   every answer ignored, in silence
        def from(config:, env:)
          file = config.slack
          new(channel: value(env, CHANNEL) || file[:channel],
            workspace: value(env, WORKSPACE) || file[:workspace],
            operators: operators(env) || Array(file[:operators]).map(&:to_s).reject(&:empty?),
            interval: file[:poll_seconds] || DEFAULT_INTERVAL)
        end

        private

        # @return [String, nil] nil for a variable that is unset or blank
        def value(env, name) = env[name].to_s.strip.then { it.empty? ? nil : it }

        # @return [Array<String>, nil]
        def operators(env)
          ids = env[OPERATORS].to_s.split(/[\s,]+/).reject(&:empty?)
          return nil if ids.empty?

          stray = ids.grep_v(USER_ID).first
          raise Error, "#{OPERATORS}: #{stray.inspect} is not a Slack user id (U0123ABCD, from a profile's \"Copy member ID\")" if stray

          ids
        end
      end
    end
  end
end
