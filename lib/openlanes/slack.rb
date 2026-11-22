# frozen_string_literal: true

module OpenLanes
  # Questions for a person, asked in a Slack channel as polls, and answered
  # there: a reaction picks an option, a reply in the thread answers in words.
  #
  # Configured by {Settings}, from `slack:` in `.openlanes/config.yml` or the
  # environment (which channel, which workspace, who may answer), and the bot
  # token in `SLACK_BOT_TOKEN`, which is a secret and so never in the file.
  # With either missing there is no bridge, and a run goes on as it would
  # without Slack.
  #
  # Nor is there one without operators. An answer in the channel
  # becomes an agent's instructions, and the agents run with a shell in
  # the repository, so who may give one is named, never "anyone there".
  module Slack
    # Seconds between two calls to Slack, unless `slack.poll_seconds` says.
    DEFAULT_INTERVAL = 2

    # Said when nobody is named who may answer.
    NO_OPERATORS = "no slack.operators in #{Config::FILE}, and no #{Settings::OPERATORS}. An answer in Slack steers an agent, " \
                   "so list the Slack user ids (U0123ABCD, from a profile's \"Copy member ID\") of the people who may give one".freeze

    # Said when there is a token and nowhere to post with it.
    NO_CHANNEL = "#{API::TOKEN_VARIABLE} is set but no channel is: set slack.channel in #{Config::FILE} or #{Settings::CHANNEL}".freeze

    module_function

    # @param env [Hash] the environment
    # @return [OpenLanes::Slack::API]
    # @raise [OpenLanes::Error] without a token
    def api(env: ENV) = API.new(token: API.token_from(env))

    # The channel the project's questions go to.
    #
    # @param config [OpenLanes::Config]
    # @param api [OpenLanes::Slack::API, nil]
    # @param env [Hash]
    # @return [OpenLanes::Slack::Room]
    # @raise [OpenLanes::Error] when no channel is configured, nobody may
    #   answer, or no token is set
    def room(config: Config.current, api: nil, env: ENV)
      settings = Settings.from(config:, env:)
      channel = settings.channel or
        raise Error, "no Slack channel. Add to #{Config::FILE}:\n\n  slack:\n    channel: \"#openlanes-questions\"\n\nor set #{Settings::CHANNEL}."
      raise Error, NO_OPERATORS unless settings.operators?

      Room.new(api: api || self.api(env:), channel:, workspace: settings.workspace, operators: settings.operators)
    end

    # The bridge a live run asks its questions through, or nil when the
    # project has not asked for one. A half of the configuration without the
    # other is said out loud, once: a token with no channel, or a channel
    # with no token, would otherwise be found out only when a question went
    # unanswered. So is one that cannot be read, which costs the polls and
    # not the run.
    #
    # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
    # @param keys [OpenLanes::Live::Keys]
    # @param config [OpenLanes::Config]
    # @param env [Hash]
    # @return [OpenLanes::Slack::Bridge, nil]
    def bridge(store:, keys:, config: Config.current, env: ENV)
      settings = Settings.from(config:, env:)
      token = API.token_from(env)
      return nil unless settings.channel || token

      if (missing = missing_for_bridge(settings, token))
        return unbridged(missing)
      end

      Bridge.new(room: room(config:, env:), outbox: Outbox.new(store:, keys:), interval: settings.interval)
    rescue Error => e
      unbridged(e.message)
    end

    # @param settings [OpenLanes::Slack::Settings]
    # @param token [String, nil]
    # @return [String, nil] what the configuration still lacks to ask in Slack
    def missing_for_bridge(settings, token)
      return "a channel is configured but #{API::TOKEN_VARIABLE} is not set" if token.nil?
      return NO_CHANNEL if settings.channel.nil?

      NO_OPERATORS unless settings.operators?
    end

    # @param why [String]
    # @return [nil]
    def unbridged(why)
      UI.log("slack: #{why}, so questions are asked in the control room only", level: :warn)
      nil
    end
  end
end
