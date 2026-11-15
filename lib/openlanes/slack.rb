# frozen_string_literal: true

module OpenLanes
  # Questions for a person, asked in a Slack channel as polls, and answered
  # there: a reaction picks an option, a reply in the thread answers in words.
  #
  # Configured by `slack:` in `.openlanes/config.yml` (which channel, which
  # workspace, who may answer) and the bot token in `SLACK_BOT_TOKEN`, which
  # is a secret and so never in the file. With either missing there is no
  # bridge, and a run goes on exactly as it did before.
  module Slack
    # Seconds between two calls to Slack, unless `slack.poll_seconds` says.
    DEFAULT_INTERVAL = 2

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
    # @raise [OpenLanes::Error] when no channel is configured, or no token set
    def room(config: Config.current, api: nil, env: ENV)
      settings = config.slack
      channel = settings[:channel] or
        raise Error, "no Slack channel. Add to #{Config::FILE}:\n\n  slack:\n    channel: \"#openlanes-questions\""

      Room.new(api: api || self.api(env:), channel:, workspace: settings[:workspace], operators: Array(settings[:operators]))
    end

    # The bridge a live run asks its questions through, or nil when the
    # project has not asked for one. A channel with no token is said out
    # loud, once: a `slack:` section that silently does nothing would be
    # found out only when a question went unanswered.
    #
    # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
    # @param keys [OpenLanes::Live::Keys]
    # @param config [OpenLanes::Config]
    # @param env [Hash]
    # @return [OpenLanes::Slack::Bridge, nil]
    def bridge(store:, keys:, config: Config.current, env: ENV)
      return nil unless config.slack[:channel]

      if API.token_from(env).nil?
        UI.log("slack: #{Config::FILE} names a channel but #{API::TOKEN_VARIABLE} is not set, so questions are asked in the control room only",
          level: :warn)
        return nil
      end
      Bridge.new(room: room(config:, env:), outbox: Outbox.new(store:, keys:), interval: config.slack[:poll_seconds] || DEFAULT_INTERVAL)
    end
  end
end
