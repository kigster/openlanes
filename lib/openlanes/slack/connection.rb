# frozen_string_literal: true

require "open3"

module OpenLanes
  module Slack
    # What joins a project to a channel: the token, the channel, the workspace
    # and the operators, gathered from what was typed and what is configured
    # already, and written to the project's `.env`.
    #
    # The `.env` and not `.openlanes/config.yml`, because the token goes
    # there in any case, and one place is easier to check than two.
    class Connection
      # A channel's id, as opposed to its name.
      CHANNEL_ID = /\A[CG][A-Z0-9]{6,}\z/

      # The channel when none is named and none is configured.
      DEFAULT_CHANNEL = "#openlanes-questions"

      # @param root [String] the project root
      # @param env [Hash] the environment
      # @param app_env [String, nil] the Slack app's own `.env`
      def initialize(root:, env: ENV, app_env: nil)
        @root = root
        @env = env
        @project = EnvFile.new(File.join(root, ".env"))
        @app = EnvFile.new(File.expand_path(app_env)) if app_env
      end

      # @return [OpenLanes::Slack::EnvFile] the project's `.env`
      attr_reader :project

      # A setting as it stands. The Slack app's file first, since it was
      # named on purpose; then what is exported; then the project's `.env`.
      #
      # @param name [String]
      # @return [String, nil] nil when unset or blank everywhere
      def [](name) = [app&.[](name), env[name], project[name]].find { !it.to_s.strip.empty? }

      # @param token [String]
      # @param operators [String] ids, separated by commas or spaces
      # @param channel [String, nil] an id, or a public channel's name
      # @param workspace [String, nil]
      # @return [Hash{String => String}] the variables a run needs
      def values(token:, operators:, channel: nil, workspace: nil)
        { API::TOKEN_VARIABLE => token,
          Settings::CHANNEL   => named(channel || self[Settings::CHANNEL] || DEFAULT_CHANNEL),
          Settings::OPERATORS => operators.split(/[\s,]+/).reject(&:empty?).join(","),
          Settings::WORKSPACE => workspace }.compact
      end

      # @param values [Hash{String => String}]
      # @return [OpenLanes::Slack::Room]
      # @raise [OpenLanes::Error] when the values cannot be asked with
      def room(values) = Slack.room(config: Config.new, env: values)

      # What each file would gain. The token goes to the project only: the
      # app's file is where it came from.
      #
      # @param values [Hash{String => String}]
      # @return [Hash{EnvFile => Hash{String => String}}]
      def changes(values)
        { project => values, app => values.except(API::TOKEN_VARIABLE) }
          .reject { |file, _| file.nil? }
          .to_h { |file, all| [file, file.changes(all)] }
          .reject { |_, changed| changed.empty? }
      end

      # @param values [Hash{String => String}]
      # @return [Hash{EnvFile => Hash{String => String}}] what was written
      def write(values) = changes(values).each { |file, changed| file.write(changed) }

      # @return [Boolean] whether git would commit the project's `.env`
      def exposed? = git?("rev-parse", "--git-dir") && !git?("check-ignore", "--quiet", "--", project.path)

      private

      # @return [Hash]
      attr_reader :env

      # @return [OpenLanes::Slack::EnvFile, nil]
      attr_reader :app

      # @return [String]
      attr_reader :root

      # A `#` is optional when typed, since a shell reads an unquoted one as
      # the start of a comment.
      #
      # @return [String]
      def named(channel) = channel.match?(CHANNEL_ID) || channel.start_with?("#") ? channel : "##{channel}"

      # @return [Boolean]
      def git?(*) = Open3.capture2e("git", "-C", root, *).last.success?
    end
  end
end
