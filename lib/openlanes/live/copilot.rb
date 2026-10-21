# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Live
    # The conversation with the run's copilot, c3po-operator (W17): one Redis
    # stream per node ({Keys#copilot}) holding every turn, the person's and
    # the copilot's, in the order they were said. The page reads it once with
    # {#history} and then follows it on the event stream it already has
    # (`event: copilot`), so the copilot needs no transport of its own.
    #
    # Who answers is the responder's business, not this class's: the API
    # server hands it {Operator}, which runs c3po-operator, and `--demo` a
    # canned line. Whatever answers writes {Turn}s, and {Turn.check} refuses
    # a card that lacks what the page needs to draw it, whoever wrote it.
    class Copilot
      # A message the person may not send as written.
      class Invalid < Error; end

      # A message nobody is there to answer.
      class Unanswered < Error; end

      # Who spoke a turn.
      SPEAKERS = %w[you copilot].freeze

      # What a turn is: words, a red card asking to confirm a command that
      # cannot be undone, or a quiet card holding a drafted answer.
      KINDS = %w[text confirm draft].freeze

      # The fields each card cannot be drawn without.
      FIELDS = {
        "text"    => [],
        "confirm" => %w[command confirm done],
        "draft"   => %w[question draft]
      }.freeze

      # Characters one message may carry. A longer one is a paste gone
      # wrong, and the agent would pay for every token of it.
      LIMIT = 4000

      # Tokens and model before the copilot has said anything that counts them.
      NO_USAGE = { model: nil, up: 0, down: 0 }.freeze

      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param responder [#call, nil] the person's {Turn} in, the copilot's
      #   {Turn}s out; nil for a reader, which {#say} refuses to write through
      def initialize(store:, keys:, responder: nil)
        @store = store
        @keys = keys
        @responder = responder
      end

      # Record the person's message, and nothing more. Answering is
      # {#answer}'s, run apart from the request that brought the message: a
      # real responder is a `claude -p` call, and a POST held open for the
      # whole of it would keep the page from showing the message, or that
      # the copilot is reading, until the answer was already written.
      #
      # A slash command ({Slash}, plan 020.00) is not the copilot's to
      # answer: it is queued for this node's engine under the message's id,
      # and the engine's reply comes back into the conversation as turn
      # `"<id>.1"`. A slash message that is not a command is answered here,
      # at once, with the usage. Neither reaches the responder, so a server
      # with no copilot still takes them, and {Turn#slash?} tells the caller
      # not to {#answer} them.
      #
      # @param input [String, Hash] `CopilotMessage`: `{id, text}`
      # @return [OpenLanes::Live::Copilot::Turn] the person's turn
      # @raise [OpenLanes::Live::Copilot::Invalid] for the API server's 422
      # @raise [OpenLanes::Live::Copilot::Unanswered] when nobody would
      #   answer: no copilot for plain text, no live engine for a command
      def say(input)
        turn = message(input)
        slash = Slash.parse(turn.text, id: turn.id)
        # Refused before it is stored: a message kept where nothing will ever
        # answer it reads, on the page, as a copilot that is merely slow.
        raise Unanswered, "the copilot is not running in this server" unless slash || @responder
        if slash.is_a?(Command) && !engine?
          raise Unanswered, "no engine is running to apply #{turn.text.split.first}"
        end

        append(turn)
        case slash
        when Command then EventBus.for(@store).append(@keys.commands, { json: JSON.generate(slash.wire) })
        when Slash::Help then append(Turn.new(id: "#{turn.id}.1", from: "copilot", kind: "text", text: slash.text))
        end
        turn
      end

      # Store whatever the responder answers to +turn+. A responder that
      # fails is answered for, under the reply id the page waits for, so the
      # failure shows in the conversation rather than as a page reading
      # forever.
      #
      # @param turn [OpenLanes::Live::Copilot::Turn] the person's, from {#say}
      # @return [Array<OpenLanes::Live::Copilot::Turn>] what was stored
      def answer(turn)
        replies = begin
          @responder.call(turn)
        rescue StandardError => e
          [Turn.new(id: "#{turn.id}.1", from: "copilot", kind: "text", text: "c3po-operator could not answer: #{e.message}")]
        end
        replies.each { append(it) }
      end

      # The conversation as the page draws it on load: the newest turns,
      # oldest first, and the copilot's latest model and tokens. The usage is
      # looked for in the whole retained stream when the newest turns carry
      # none, so a run of unmetered turns does not reset the header to zero.
      #
      # @param count [Integer]
      # @return [Hash] `CopilotLog`: `{turns:, usage:}`
      def history(count: 100)
        turns = newest_turns(count)
        usage = latest_usage(turns)
        usage ||= latest_usage(newest_turns(Keys::COPILOT_LENGTH)) if turns.size == count
        { turns:, usage: usage || NO_USAGE }
      end

      # Turns written after +after+, oldest first, with their stream ids.
      #
      # @param after [String] a stream id
      # @return [Array<Array(String, Hash)>]
      def since(after)
        @store.xread(@keys.copilot, id: after).map { |entry| [entry.id, JSON.parse(entry.fields["json"])] }
      end

      # @return [String] the newest turn's stream id, `0-0` when there is none
      def newest = @store.xrevrange(@keys.copilot, count: 1).first&.id || "0-0"

      private

      # @return [OpenLanes::Live::Copilot::Turn]
      def message(input)
        data = input.is_a?(String) ? JSON.parse(input) : input
        raise Invalid, "a message is a JSON object" unless data.is_a?(Hash)

        id = data["id"].to_s
        text = data["text"].to_s.strip
        raise Invalid, "id must be 1 to 64 letters, digits, - or _" unless id.match?(Command::ID)
        raise Invalid, "a message needs text" if text.empty?
        raise Invalid, "a message is at most #{LIMIT} characters" if text.length > LIMIT

        Turn.new(id:, from: "you", kind: "text", text:)
      rescue JSON::ParserError => e
        raise Invalid, "not a message: #{e.message.lines.first.to_s.strip}"
      end

      # @return [Array<Hash>] up to +count+ turns, oldest first
      def newest_turns(count)
        @store.xrevrange(@keys.copilot, count:).reverse.map { JSON.parse(it.fields["json"]) }
      end

      # Whether this node's engine is there to read {Keys#commands}: its
      # snapshot key lives only while it publishes (`EX 30`), so a command
      # queued without one would sit unanswered and the page would read on.
      #
      # @return [Boolean]
      def engine? = !@store.get(@keys.snapshot).nil?

      # @return [Hash, nil]
      def latest_usage(turns) = turns.reverse_each.map { it["usage"] }.find(&:itself)

      # Written here, in the API server rather than by the Dispatcher, so the
      # open streams are nudged here too: a turn has no other way to reach a
      # stream that waits on {Keys#news}.
      #
      # @return [void]
      def append(turn)
        EventBus.for(@store).append(@keys.copilot, { json: turn.to_json }, maxlen: Keys::COPILOT_LENGTH)
        News.publish(store: @store, keys: @keys, kind: "copilot")
      end
    end

    class Copilot
      # One thing said in the conversation: `CopilotTurn` in `types.ts`.
      #
      # @!attribute [r] id
      #   @return [String] the person's message id; a reply's is that id, a
      #     dot and its place among the replies, so a reply names what it answers
      # @!attribute [r] from
      #   @return [String] one of {SPEAKERS}
      # @!attribute [r] kind
      #   @return [String] one of {KINDS}
      # @!attribute [r] text
      #   @return [String]
      # @!attribute [r] at
      #   @return [Time]
      # @!attribute [r] usage
      #   @return [Hash, nil] `{model, up, down}`, the copilot's running total
      #     after this turn; nil on the person's turns and on answers no model
      #     wrote
      # @!attribute [r] fields
      #   @return [Hash{String => Object}] what a card needs, per {FIELDS}
      Turn = Data.define(:id, :from, :kind, :text, :at, :usage, :fields) do
        def initialize(at: Time.now, usage: nil, fields: {}, **rest)
          super
          Turn.check(self)
        end

        # @return [Hash] as the wire carries it
        def wire = { id:, from:, kind:, text:, at: at.utc.iso8601, usage: }.merge(fields.transform_keys(&:to_sym))

        # @return [Boolean] whether this is the person's slash message, which
        #   the engine or {Slash} answers and the copilot never does
        def slash? = from == "you" && text.start_with?("/")

        # @return [String]
        def to_json(*) = JSON.generate(wire)
      end

      class Turn
        # The keys every turn has; anything else belongs to {FIELDS}.
        BASE = %w[id from kind text at usage].freeze

        # @param data [Hash] a turn as the wire carries it
        # @return [OpenLanes::Live::Copilot::Turn]
        # @raise [OpenLanes::Live::Copilot::Invalid]
        def self.parse(data)
          data = data.transform_keys(&:to_s)
          new(id: data["id"].to_s,
            from: data["from"].to_s,
            kind: data["kind"].to_s,
            text: data["text"].to_s,
            at: data["at"] ? Time.iso8601(data["at"]) : Time.now,
            usage: data["usage"],
            fields: data.except(*BASE))
        rescue ArgumentError => e
          raise Invalid, "not a turn: #{e.message}"
        end

        # @param turn [OpenLanes::Live::Copilot::Turn]
        # @return [void]
        # @raise [OpenLanes::Live::Copilot::Invalid] naming what is wrong
        def self.check(turn)
          raise Invalid, "unknown speaker #{turn.from.inspect}" unless SPEAKERS.include?(turn.from)
          raise Invalid, "unknown kind #{turn.kind.inspect}; known: #{KINDS.join(", ")}" unless KINDS.include?(turn.kind)
          raise Invalid, "only the copilot draws cards" if turn.from == "you" && turn.kind != "text"

          fields = turn.fields.transform_keys(&:to_s)
          check_names(turn.kind, fields.keys)
          check_text(turn.kind, fields)
          check_command(fields["command"]) if turn.kind == "confirm"
        end

        # A card holds exactly its own fields: a missing one cannot be drawn,
        # and an extra one could shadow a base key such as `id` on the wire.
        #
        # @return [void]
        def self.check_names(kind, names)
          wanted = FIELDS.fetch(kind)
          missing = wanted - names
          raise Invalid, "a #{kind} card needs #{missing.join(" and ")}" unless missing.empty?

          extra = names - wanted
          raise Invalid, "a #{kind} card has no #{extra.join(" or ")}" unless extra.empty?
        end

        # Every field but a command is drawn as text, so it has to be some:
        # a blank one would draw an unnamed button or an empty draft.
        #
        # @return [void]
        def self.check_text(kind, fields)
          wrong = (FIELDS.fetch(kind) - %w[command]).reject { fields[it].is_a?(String) && !fields[it].strip.empty? }
          raise Invalid, "a #{kind} card's #{wrong.join(" and ")} must be text" unless wrong.empty?
        end

        # A confirm card is sent through the same gate as the page's own
        # buttons (W13), so it has to be a command that gate would take. It
        # carries no id: the page mints one when the person presses, and an id
        # supplied here would replace it and could repeat one already done.
        #
        # @return [void]
        def self.check_command(command)
          raise Invalid, "a confirm card's command is a JSON object" unless command.is_a?(Hash)

          command = command.transform_keys(&:to_s)
          raise Invalid, "a confirm card's command carries no id; the page mints one" if command.key?("id")

          Command.parse(command.merge("id" => "card"))
        rescue Command::Invalid => e
          raise Invalid, "a confirm card's command is not one: #{e.message}"
        end
      end
    end
  end
end
