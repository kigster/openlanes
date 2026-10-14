# frozen_string_literal: true

module OpenLanes
  module Plans
    # The one channel two agents on the same plan have to each other.
    #
    # `luke-backend` and `rey-frontend` build one plan in one worktree at the
    # same time, but each is its own `claude -p` process. Claude Code can
    # message between local sessions, and the prompts used to say so, but a
    # session is named after its directory plus a random suffix, so a pair had
    # to guess its partner from a list of every session on the machine by start
    # time. It worked once, by luck. With ten plans running there would have
    # been ten `openlanes-xx` entries and nothing to tell them apart.
    #
    # So the mailbox lives in the plan folder, append-only, one numbered entry
    # per message, readable by `openlanes mail read` during the round and by a
    # person after it. The harness names the partner in each agent's prompt,
    # so nobody guesses.
    #
    # Messages are kept in the plan's `state.json` ({PlanState}), next to the
    # stages and signatures a restart reads. Plans from before that kept them
    # in `mailbox.md`; those are still read, and numbering carries on from
    # them, but nothing writes there any more.
    class Mailbox
      # Where messages used to be written, and are still read from.
      FILENAME = "mailbox.md"

      # Between the fields of a heading. Neither a name nor a timestamp
      # contains it, which is what makes the heading parseable.
      SEPARATOR = " · "

      # `## 3 · 2026-09-06 10:30:53 -0700 · rey-frontend → luke-backend`
      HEADING = /\A\#\# (\d+) · (.+?) · (\S+) → (\S+)\s*\z/

      TIME_FORMAT = "%Y-%m-%d %H:%M:%S %z"

      # One entry.
      #
      # @!attribute [r] number
      #   @return [Integer] 1-based, in order of writing
      # @!attribute [r] at
      #   @return [String] when, as {TIME_FORMAT} writes it
      # @!attribute [r] from
      #   @return [String] the agent that wrote it
      # @!attribute [r] to
      #   @return [String] the agent it is for
      # @!attribute [r] body
      #   @return [String]
      # @!attribute [r] read
      #   @return [String] "yes" once its recipient ran `mail ack`, "no" until
      #     then. Set by the reader, never by delivery: a stream ack says the
      #     bytes arrived, not that anybody read them.
      Message = Data.define(:number, :at, :from, :to, :body, :read) do
        # A message written before acks existed carries no `read`, and reads
        # as unread: nobody ever said they read it.
        def initialize(number:, at:, from:, to:, body:, read: "no") = super

        # @return [Boolean]
        def read? = read == "yes"

        # @return [String] as it stands in the file
        def to_s = "## #{number}#{SEPARATOR}#{at}#{SEPARATOR}#{from} → #{to}\n\n#{body.strip}\n"
      end

      # @param dir [String] the plan folder
      def initialize(dir:)
        @dir = dir
      end

      # @return [String] the plan folder
      attr_reader :dir

      # @return [String] where new messages are written
      def path = state.path

      # @return [String] where messages from before `state.json` are read
      def legacy_path = File.join(dir, FILENAME)

      # @return [Boolean] whether any message has been written
      def exist? = !messages.empty?

      # Every message, in the order it was written.
      #
      # @return [Array<OpenLanes::Plans::Mailbox::Message>]
      def messages
        (legacy + state.messages.map { |m| from_state(m) }).sort_by(&:number)
      end

      # What is waiting for one agent.
      #
      # @param name [String] the reader
      # @param after [Integer] a number the reader has already seen; only
      #   messages above it are returned
      # @return [Array<OpenLanes::Plans::Mailbox::Message>]
      def for(name, after: 0)
        messages.select { |m| m.to == name && m.number > after }
      end

      # Append one message and give it the next number.
      #
      # {PlanState} takes a lock around the read and the write, so two agents
      # finishing a unit in the same second cannot both take the same number.
      #
      # @param from [String]
      # @param to [String]
      # @param body [String]
      # @param at [Time]
      # @param command [String, nil] the page command that sent it; the same
      #   id to the same reader appends nothing the second time
      # @return [OpenLanes::Plans::Mailbox::Message] as written, or as first
      #   written under +command+
      # @raise [OpenLanes::Error] on an empty body, which would be a heading
      #   with nothing under it for the reader to act on, or on a sender or
      #   recipient that is blank or holds whitespace
      def append(from:, to:, body:, at: Time.now, command: nil)
        text = body.to_s.strip
        raise Error, "a message needs a body" if text.empty?
        raise Error, "a message needs --from and --to, each one agent name" unless name?(from) && name?(to)

        from_state(state.message!(from:, to:, body: text, at:, after: legacy.map(&:number).max.to_i, command:))
      end

      # Keep a message the harness drained from Redis, unless this plan
      # already has its number, here or in `mailbox.md`.
      #
      # @param message [Hash] as {Live::Mail#drain} returns it
      # @return [OpenLanes::Plans::Mailbox::Message, nil] as written, nil when
      #   it was already here
      # @raise [OpenLanes::Error] for one with no positive number, no body,
      #   or a sender or recipient that is not one agent name
      def deliver(message)
        number = message["number"]
        raise Error, "a delivered message needs a positive number" unless number.is_a?(Integer) && number.positive?
        raise Error, "a message needs a body" if message["body"].to_s.strip.empty?
        raise Error, "a message needs --from and --to, each one agent name" unless name?(message["from"]) && name?(message["to"])
        return nil if legacy.any? { |m| m.number == number }

        state.deliver!(message)&.then { from_state(it) }
      end

      # How many messages nobody has acked. The dashboard shows it, and
      # nothing else reads it: an unacked message is a warning, never an input
      # to a round (D3).
      #
      # @param recipient [String, nil] one reader, or everybody
      # @return [Integer]
      def unacked(recipient = nil)
        messages.count { |m| !m.read? && (recipient.nil? || m.to == recipient) }
      end

      # Mark one message read.
      #
      # @param number [Integer]
      # @param by [String] the reader, who must be its recipient
      # @return [OpenLanes::Plans::Mailbox::Message] as it stands now
      # @raise [OpenLanes::Error] for a number with no message, or a reader
      #   it was not addressed to
      def ack(number, by:)
        number = Integer(number.to_s, exception: false)
        raise Error, "a message number is a positive integer" unless number&.positive?

        if (old = legacy.find { |m| m.number == number })
          raise Error, "message ##{number} is for #{old.to}, not #{by}" unless old.to == by

          return old
        end

        message = state.ack!(number, by:)
        raise Error, "no message ##{number} in #{File.basename(dir)}" unless message

        from_state(message)
      end

      # The whole exchange as Markdown, for a person after the round. Returns
      # the text and writes nothing: the JSON is the record, and a rendered
      # copy beside it would be a second one to drift.
      #
      # @return [String]
      def render
        title = "# Mailbox: #{File.basename(dir)}\n"
        return "#{title}\nNo messages.\n" if messages.empty?

        entries = messages.map do |m|
          "## #{m.number}#{SEPARATOR}#{m.at}#{SEPARATOR}#{m.from} → #{m.to}#{SEPARATOR}" \
            "#{m.read? ? "read" : "unread"}\n\n#{m.body.strip}\n"
        end
        ([title] + entries).join("\n")
      end

      private

      # @return [OpenLanes::Plans::PlanState]
      def state = PlanState.for(dir)

      # @return [Array<OpenLanes::Plans::Mailbox::Message>] what mailbox.md holds
      def legacy
        return [] unless File.file?(legacy_path)

        parse(File.read(legacy_path, encoding: "UTF-8"))
      end

      # @param message [Hash] as {PlanState} stores it
      # @return [OpenLanes::Plans::Mailbox::Message]
      def from_state(message)
        at = begin
          Time.iso8601(message["at"].to_s).strftime(TIME_FORMAT)
        rescue ArgumentError
          message["at"].to_s
        end
        Message.new(number: message["number"],
          at:,
          from: message["from"],
          to: message["to"],
          body: message["body"],
          read: message["read"] == "yes" ? "yes" : "no")
      end

      # @param value [Object]
      # @return [Boolean] one token, as {HEADING} expects a name to be
      def name?(value) = value.to_s.match?(/\A\S+\z/)

      # Only a line shaped exactly like {HEADING} starts a message, so a body
      # may hold headings of its own, code, anything.
      #
      # @param text [String]
      # @return [Array<OpenLanes::Plans::Mailbox::Message>]
      def parse(text)
        messages = []
        current = nil
        body = []

        text.to_s.each_line(chomp: true) do |line|
          if (heading = HEADING.match(line))
            messages << current.with(body: body.join("\n").strip) if current
            # mailbox.md predates acking, and nobody is left to ack it: it
            # is history, so it counts as read rather than as a warning forever.
            current = Message.new(number: heading[1].to_i,
              at: heading[2],
              from: heading[3],
              to: heading[4],
              body: "",
              read: "yes")
            body = []
          elsif current
            body << line
          end
        end

        messages << current.with(body: body.join("\n").strip) if current
        messages
      end
    end
  end
end
