# frozen_string_literal: true

require "digest"
require "json"

module OpenLanes
  module Slack
    # One question as a Slack poll: how it is drawn, which emoji stands for
    # which option, and how a message read back from Slack becomes an answer.
    #
    # It reads the question exactly as the control room's snapshot carries
    # it (`Question` in `web/src/api/types.ts`), so the channel and the page
    # show the same words and offer the same choices. Pure: a Hash in,
    # blocks and values out, no network.
    #
    # @example
    #   poll = Slack::Poll.new(plan: { "ordinal" => "041.00", "title" => "Idle Start" }, question:)
    #   poll.blocks                       # Block Kit, one numbered line per option
    #   poll.read(messages, bot: "UBOT")  # => Vote, or nil while nobody has answered
    class Poll
      # The reactions a poll offers, first option first. Nine is every digit
      # Slack has a keycap for, and D3 caps a question at five options.
      EMOJI = %w[one two three four five six seven eight nine].freeze

      # The most text one Block Kit section takes is 3000 characters.
      LIMIT = 2800

      # An answer read off a message.
      #
      # @!attribute [r] user
      #   @return [String] the Slack user id of whoever answered
      # @!attribute [r] text
      #   @return [String] what the engine is told: an option's `answer`, or
      #     the words of a thread reply, as said
      # @!attribute [r] label
      #   @return [String] how the answer reads in the channel, escaped, so
      #     a reply cannot ping `<!channel>` when it is echoed back
      Vote = Data.define(:user, :text, :label)

      # @param plan [Hash] `ordinal` and `title`, string keys
      # @param question [Hash] the snapshot's `Question`, string keys
      def initialize(plan:, question:)
        @plan = plan
        @question = question
      end

      # @return [Hash]
      attr_reader :plan

      # @return [Hash]
      attr_reader :question

      # @return [String] the plan's ordinal
      def ordinal = plan["ordinal"].to_s

      # What the `answer` command calls the question: `B2`, `X1`, or the
      # quality question's name. The id is `<ordinal>/<that>`.
      #
      # @return [String]
      def ref = question["id"].to_s.split("/", 2).last.to_s

      # Which question this is, for as long as it is asked. The heading and
      # not the body, because the engine rewrites a prose body into choices
      # after the question is first seen (D9), and that is the same question;
      # the heading as well as the id, because `blocked.md` numbers from B1
      # every time a plan blocks.
      #
      # @return [String]
      def key = "#{question["id"]}##{Digest::SHA256.hexdigest(question["heading"].to_s)[0, 12]}"

      # @return [String] changes whenever the drawn message would
      def digest = Digest::SHA256.hexdigest(JSON.generate(blocks))[0, 16]

      # @return [Array<Hash>] the options, each `letter`, `label`, `recommended`, `answer`
      def options = Array(question["options"]).first(EMOJI.size)

      # @return [Array<String>] one emoji per option
      def emoji = EMOJI.first(options.size)

      # Escaped like the blocks: Slack reads `<!channel>` and `<url|label>`
      # in a notification's text as well.
      #
      # @return [String] the line a notification shows
      def text = escape("#{ordinal} #{plan["title"]}: #{question["heading"]}".strip)

      # @param closing [String, nil] what happened to the question, once
      #   something has; nil while it is open
      # @return [Array<Hash>] Block Kit
      def blocks(closing = nil)
        sections = [title, "*#{mrkdwn(question["heading"])}*", *question.values_at("follow_up", "body").map { mrkdwn(it) }, choices]
        sections.reject { it.to_s.strip.empty? }.map { section(it) } << context(closing || invitation)
      end

      # The control room's own `answer` command ({Live::Command}). Its id
      # comes from the message, so an answer read twice over a crash is
      # applied once (W13).
      #
      # @param text [String] what the engine is told
      # @param stamp [String] the `ts` of the poll's message
      # @return [Hash]
      def command(text:, stamp:)
        { "id"      => "slack-#{Digest::SHA256.hexdigest("#{key}/#{stamp}")[0, 32]}",
          "kind"    => "answer",
          "plan"    => ordinal,
          "agent"   => question["agent"],
          "payload" => { "question" => ref, "text" => text } }
      end

      # The answer a message carries, if it carries one yet.
      #
      # A reaction on an option wins over a reply, and the lowest-numbered
      # option an operator chose wins over the others, since Slack does not
      # say which reaction came first: a poll with two votes is still one
      # decision, and the engine can only be told one.
      #
      # Nobody's answer counts without operators. A `blocked.md` answer is
      # prose an agent reads as instructions, and "anyone in the channel"
      # takes in whoever joins it, a Slack Connect guest from another
      # organisation among them.
      #
      # @param messages [Array<Hash>] the message and then its thread, as
      #   `conversations.replies` returns them
      # @param bot [String] the bot's own user id, whose reactions are the
      #   ballot and not a vote
      # @param operators [Array<String>] user ids allowed to answer; empty
      #   lets nobody
      # @param reactions [Array<Hash>, nil] the message's reactions when
      #   they were read apart from it
      # @return [Vote, nil]
      def read(messages, bot:, operators: [], reactions: nil)
        parent, *replies = messages
        allowed = ->(user) { user && user != bot && operators.include?(user) }
        chosen(reactions || parent.to_h["reactions"], allowed) || replied(replies, allowed)
      end

      private

      # @return [Vote, nil]
      def chosen(reactions, allowed)
        by_name = Array(reactions).to_h { [it["name"].to_s, Array(it["users"])] }
        options.zip(emoji).each do |option, name|
          user = by_name.fetch(name, []).find(&allowed) or next
          return Vote.new(user:, text: option["answer"].to_s, label: escape(option["label"]))
        end
        nil
      end

      # @return [Vote, nil]
      def replied(replies, allowed)
        said = replies.find { it["bot_id"].nil? && allowed.call(it["user"]) && !it["text"].to_s.strip.empty? } or return nil
        Vote.new(user: said["user"], text: said["text"].strip, label: escape(said["text"].strip))
      end

      # @return [String] which plan, who asks, and whose question it is
      def title
        asker = question["agent"] ? "#{escape(question["agent"])} asks" : "the engine asks"
        "*#{escape(ordinal)} #{escape(plan["title"])}* · #{asker} · #{escape(question["owner"] || "technical")}"
      end

      # @return [String, nil]
      def choices
        return nil if options.empty?

        options.zip(emoji).map { |option, name| ":#{name}:  #{mrkdwn(option["label"])}#{"  _(recommended)_" if option["recommended"]}" }.join("\n")
      end

      # @return [String]
      def invitation
        return "Reply in this thread to answer." if options.empty?

        "React with a number to choose, or reply in this thread to answer in your own words."
      end

      # @return [Hash]
      def section(text) = { type: "section", text: { type: "mrkdwn", text: } }

      # @return [Hash]
      def context(text) = { type: "context", elements: [{ type: "mrkdwn", text: }] }

      # Markdown as Slack reads it: `&`, `<` and `>` escaped, `**bold**` as
      # `*bold*`, and cut to what a section holds.
      #
      # @param text [String, nil]
      # @return [String]
      def mrkdwn(text)
        said = escape(text.to_s.strip).gsub(/\*\*(.+?)\*\*/m, '*\1*').gsub(/^&gt; ?/, "> ")
        said.size > LIMIT ? "#{said[0, LIMIT]}…" : said
      end

      # @return [String]
      def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end
  end
end
