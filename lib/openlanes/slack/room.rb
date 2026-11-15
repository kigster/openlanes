# frozen_string_literal: true

module OpenLanes
  module Slack
    # The channel the questions go to, in the workspace they are meant for.
    #
    # A bot token belongs to one workspace, so "which workspace" is not
    # something a call can choose: it is something to check. `slack.workspace`
    # names the one intended, and a token that turns out to belong to another
    # is refused before a single question is posted, rather than an agent's
    # question about one company's code landing in another company's Slack.
    class Room
      # Where one poll sits.
      #
      # @!attribute [r] channel
      #   @return [String] the channel's id, as Slack returned it
      # @!attribute [r] ts
      #   @return [String] the message's timestamp, which is its id
      Ref = Data.define(:channel, :ts)

      # What to do about the refusals a person can fix without a restart.
      HINTS = {
        "not_in_channel"    => "invite the app to the channel: /invite @<the app's name>",
        "channel_not_found" => "check slack.channel; a private channel must be given by id, and the app invited to it",
        "invalid_auth"      => "#{API::TOKEN_VARIABLE} is not a token Slack knows",
        "missing_scope"     => "add the scope under OAuth & Permissions, then reinstall the app"
      }.freeze

      # @param api [OpenLanes::Slack::API]
      # @param channel [String] an id, or a public channel's `#name`
      # @param workspace [String, nil] the team's id, name or subdomain the
      #   token must belong to; nil takes whichever it does
      # @param operators [Array<String>] user ids allowed to answer; empty
      #   lets anyone in the channel
      def initialize(api:, channel:, workspace: nil, operators: [])
        @api = api
        @channel = channel
        @workspace = workspace
        @operators = operators
        @names = {}
      end

      # @return [String]
      attr_reader :channel

      # Who the token is, once it is known to be in the right workspace.
      #
      # @return [Hash] `team`, `team_id`, `url`, `user_id`
      # @raise [OpenLanes::Error] when the token belongs to another workspace
      def identity
        @identity ||= @api.identity.tap do |who|
          next if @workspace.nil? || names_of(who).include?(@workspace.to_s.downcase)

          raise Error,
            "slack.workspace is #{@workspace}, but #{API::TOKEN_VARIABLE} belongs to #{who["team"]} " \
            "(#{who["team_id"]}, #{who["url"]}). Nothing was posted."
        end
      end

      # @return [String] the bot's own user id
      def bot = identity.fetch("user_id")

      # Post the question, without its ballot: {#decorate} adds that, so a
      # caller can write down where the message is before anything else can
      # fail and a second message be posted in its place.
      #
      # @param poll [OpenLanes::Slack::Poll]
      # @return [Ref]
      def post(poll)
        identity
        sent = hinted { @api.post(channel: @channel, text: poll.text, blocks: poll.blocks) }
        Ref.new(channel: sent.fetch("channel"), ts: sent.fetch("ts"))
      end

      # Draw the message as the poll now reads and put one reaction on it
      # per option, in order, for a person to click.
      #
      # @param ref [Ref]
      # @param poll [OpenLanes::Slack::Poll]
      # @return [void]
      def decorate(ref, poll)
        hinted do
          @api.update(channel: ref.channel, at: ref.ts, text: poll.text, blocks: poll.blocks)
          poll.emoji.each { @api.react(channel: ref.channel, at: ref.ts, name: it) }
        end
      end

      # @param ref [Ref]
      # @param poll [OpenLanes::Slack::Poll]
      # @return [OpenLanes::Slack::Poll::Vote, nil] nil while nobody has answered
      def vote(ref, poll)
        messages = hinted { @api.thread(channel: ref.channel, at: ref.ts) }
        # The bot's own ballot is always on a poll with options, so a message
        # that comes back with no reactions at all did not bring them.
        reactions = (@api.reactions(channel: ref.channel, at: ref.ts) if poll.options.any? && !messages.first.to_h.key?("reactions"))
        poll.read(messages, bot:, operators: @operators, reactions:)
      end

      # Say on the message what became of the question, in place of the
      # invitation to answer it.
      #
      # @param ref [Ref]
      # @param poll [OpenLanes::Slack::Poll]
      # @param closing [String]
      # @return [void]
      def close(ref, poll, closing)
        hinted { @api.update(channel: ref.channel, at: ref.ts, text: poll.text, blocks: poll.blocks(closing)) }
      end

      # A person's name for the record in `blocked.md`. Reading it needs the
      # `users:read` scope, which the poll itself does not, so an app without
      # it signs answers with the user's id.
      #
      # @param user [String] a user id
      # @return [String]
      def name_of(user)
        @names[user] ||= @api.user(user).then { it["real_name"].to_s.strip.then { |name| name.empty? ? user : name } }
      rescue Error
        user
      end

      private

      # @return [Array<String>] every way to name the workspace, lower case
      def names_of(who)
        [who["team_id"], who["team"], who["url"].to_s[%r{//([^./]+)\.}, 1]].compact.map { it.to_s.downcase }
      end

      # @raise [OpenLanes::Error] Slack's refusal, with what to do about it
      def hinted
        yield
      rescue API::Refused => e
        hint = HINTS[e.code] or raise
        raise Error, "#{e.message}; #{hint}"
      end
    end
  end
end
