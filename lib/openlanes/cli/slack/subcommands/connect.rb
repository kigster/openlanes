# frozen_string_literal: true

require "tty-prompt"

module OpenLanes
  module CLI
    # `openlanes slack …`
    module Slack
      # `slack connect OPERATORS [CHANNEL]` — from nothing to a run that asks
      # its questions in Slack: say how to create the app when there is no
      # token, check the token and its workspace, write the settings to the
      # project's `.env`, and post a test poll in the channel.
      class Connect < Base
        desc "Ask this project's questions in a Slack channel: write the settings to .env, then post a test poll"

        argument :operators, required: true, desc: "Slack user ids whose answers count, comma separated (a profile's \"Copy member ID\")"
        argument :channel,
          required: false,
          desc:     "The channel's id (C0123ABCD), or a public channel's name; " \
                    "the one configured, or #{OpenLanes::Slack::Connection::DEFAULT_CHANNEL}, by default"
        option :workspace, desc: "The team id the token must belong to; the token's own by default"
        option :app_env, desc: "The Slack app's .env: the token is read from it, and the settings written there too"
        option :test, type: :boolean, default: true, desc: "Post a test poll and wait for an answer"
        option :timeout, type: :integer, default: 120, desc: "Seconds to wait for somebody to answer the test poll"
        dry_run_option "Print what would be written, and post nothing"

        example [
          "U0123ABCD                                      # the default channel",
          "U0123ABCD,U0456EFGH C0123ABCD --no-test        # two operators, a private channel",
          "U0123ABCD questions --app-env ../app/.env      # the token is in the Slack app's .env"
        ]

        TOKEN = OpenLanes::Slack::API::TOKEN_VARIABLE
        WORKSPACE = OpenLanes::Slack::Settings::WORKSPACE

        # @param env [Hash] the environment
        # @param prompt [TTY::Prompt, nil] asks for the token; nil makes one,
        #   when there is a terminal to ask on
        def initialize(env: ENV, prompt: nil)
          super()
          @env = env
          @prompt = prompt
        end

        # @param options [Hash]
        # @return [void]
        def call(**options)
          connection = OpenLanes::Slack::Connection.new(root: Dir.pwd, env:, app_env: options[:app_env])
          values = checked(connection, options)
          return preview(connection, values) if options[:dry_run]

          write(connection, values)
          Test.new.trial(connection.room(values), options[:timeout]) if options.fetch(:test, true)
          say("Reload the environment so SLACK_BOT_TOKEN and the rest are set (direnv does), then run `openlanes start`.")
        rescue OpenLanes::Error => e
          refuse(e.message, 69)
        end

        private

        # @return [Hash]
        attr_reader :env

        # The settings, once Slack has said whose token it is.
        #
        # @return [Hash{String => String}]
        def checked(connection, options)
          refuse("#{connection.project.path} is not ignored by git, and the token goes in it. Add .env to .gitignore.", 77) if connection.exposed?

          values = connection.values(token: connection[TOKEN] || asked, **options.slice(:operators, :channel, :workspace))
          who = connection.room(values).identity
          say("Workspace #{paint(who["team"].to_s, :cyan)} (#{who["team_id"]}), token of #{who["user"]}")
          values.merge(WORKSPACE => who["team_id"])
        end

        # @return [String] the token, typed by a person who has just made the app
        def asked
          say("No #{TOKEN} yet. Create the Slack app (the link fills the form in), install it to the workspace, " \
              "then copy the Bot User OAuth Token from OAuth & Permissions:\n\n  #{OpenLanes::Slack::AppManifest.create_url}\n")
          token = prompt&.mask("Bot User OAuth Token (xoxb-…):").to_s.strip
          return token unless token.empty?

          refuse("Set #{TOKEN} and run this again, or name the Slack app's .env with --app-env.", 64)
        end

        # @return [void]
        def preview(connection, values)
          connection.changes(values).each { |file, changed| say("Would write #{changed.keys.join(", ")} to #{file.path}") }
          say("Dry run: nothing was written or posted.")
        end

        # @return [void]
        def write(connection, values)
          connection.write(values).each { |file, changed| say("Wrote #{changed.keys.join(", ")} to #{file.path}") }
        end

        # @return [TTY::Prompt, nil] nil with nobody at a terminal to ask
        def prompt = @prompt ||= ($stdin.tty? && $stderr.tty? ? TTY::Prompt.new(output: $stderr) : nil)
      end
    end
  end
end
