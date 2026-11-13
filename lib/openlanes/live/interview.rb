# frozen_string_literal: true

require "json"
require "securerandom"
require "time"

module OpenLanes
  module Live
    # The unblocker's interview on one open question (plan 068): one Redis
    # stream per plan and question ({Keys#interview}), holding every turn in
    # the order it was said. Nothing here touches the plan's files: the one
    # write is `confirm_interview`'s, after the person confirms, so an
    # interview left half-way changes nothing on disk.
    #
    # Kept in the store rather than in the page, so a reload or a second
    # machine shows the same conversation.
    class Interview
      # A turn the page could not draw honestly.
      class Invalid < Error; end

      # Who spoke a turn.
      SPEAKERS = %w[you unblocker].freeze

      # Words, a question with lettered options, or the decision to confirm.
      KINDS = %w[text question decision].freeze

      # A label that means nothing on a card read alone: B2, A9, U3, D1.
      LABEL = /\b[BAUD]\d+\b/

      # Characters one message may carry, as for the copilot.
      LIMIT = 4000

      # Turns one interview keeps, approximately.
      LENGTH = 200

      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param plan [String] the plan's ordinal
      # @param number [Integer, String] the question's number
      def initialize(store:, keys:, plan:, number:)
        @store = store
        @keys = keys
        @plan = plan.to_s
        @number = number.to_i
      end

      # @return [String]
      attr_reader :plan

      # @return [Integer]
      attr_reader :number

      # @return [Array<OpenLanes::Live::Interview::Turn>] oldest first
      def history = @store.xrange(key, count: LENGTH).map { Turn.parse(JSON.parse(it.fields["json"])) }

      # Store +turn+, and publish it to the open pages as `event: interview`.
      #
      # @param turn [OpenLanes::Live::Interview::Turn]
      # @return [OpenLanes::Live::Interview::Turn]
      def say(turn)
        EventBus.for(@store).append(key, { json: turn.to_json }, maxlen: LENGTH)
        Feed.new(store: @store, keys: @keys).append(plan:, number:, turn:)
        News.publish(store: @store, keys: @keys, kind: "interview")
        turn
      end

      # How long one reply may hold the interview before another may start,
      # in seconds: longer than a slow model's turn, short enough that a
      # crashed server does not silence the interview for good.
      BUSY = 600

      # Store what +responder+ says next, when the person is owed a turn: the
      # interview is empty, or the person spoke last. One reply runs at a
      # time per question (F2): a second caller, say a reload while the
      # opening question is still being written, leaves a note and returns,
      # and the one running looks again once it is done, so a turn said
      # meanwhile is still answered, and answered once.
      #
      # A responder that fails is answered for in plain words, never as a
      # refusal of what the person said, so the page shows why it went quiet
      # and the buttons stay usable.
      #
      # @param responder [#call] given this interview, returns its next {Turn}s
      # @return [Array<OpenLanes::Live::Interview::Turn>] what was stored
      def reply(responder)
        said = []
        while (turns = held { owed? ? answer(responder) : [] })
          said.concat(turns)
          break unless @store.get(again_key)
        end
        said
      end

      # @return [Boolean] whether the person waits on the unblocker
      def owed?
        last = history.last
        last.nil? || last.from == "you"
      end

      # An id for the unblocker's next turn. Random rather than counted from
      # the history, so two replies that read the same history cannot mint
      # the same id.
      #
      # @return [String]
      def next_id = "u#{SecureRandom.alphanumeric(12)}"

      # The decision turn +id+, or nil when there is none by that id.
      #
      # @param id [String]
      # @return [OpenLanes::Live::Interview::Turn, nil]
      def decision(id) = history.find { it.id == id.to_s && it.kind == "decision" }

      # Forget the conversation: the question is answered, so it is over.
      #
      # @return [void]
      def close = @store.del(key, busy_key, again_key)

      # @return [Hash] `{turns: [InterviewTurn]}`, as the API serves it
      def wire = { turns: history.map(&:wire) }

      private

      # Run the block holding the interview, or leave a note for the holder.
      #
      # @return [Object, nil] the block's value, nil when another reply holds it
      def held
        @store.set(again_key, "1", ex: BUSY)
        token = SecureRandom.hex(8)
        return unless @store.set(busy_key, token, ex: BUSY, nx: true)

        begin
          @store.del(again_key)
          yield
        ensure
          @store.compare_and_delete(busy_key, token)
        end
      end

      # @return [Array<OpenLanes::Live::Interview::Turn>] what was stored
      def answer(responder)
        turns = begin
          responder.call(self)
        rescue StandardError => e
          [Turn.new(id: next_id,
            from: "unblocker",
            kind: "text",
            text: "The interview could not go on (#{e.message.lines.first.to_s.strip}). The answer buttons still work.")]
        end
        turns.each { say(it) }
      end

      # @return [String]
      def key = @keys.interview(@plan, @number)

      # @return [String] held while a reply is being written
      def busy_key = "#{key}:busy"

      # @return [String] set by a caller that found a reply under way
      def again_key = "#{key}:again"
    end

    class Interview
      # One thing said in the interview: `InterviewTurn` in `types.ts`.
      Turn = Data.define(:id, :from, :kind, :text, :at, :options, :answer) do
        def initialize(at: Time.now, options: nil, answer: nil, **rest)
          super
          Turn.check(self)
        end

        # @return [Hash] as the wire carries it
        def wire
          { id:, from:, kind:, text:, at: at.utc.iso8601 }.tap do |hash|
            hash[:options] = options if kind == "question"
            hash[:answer] = answer if kind == "decision"
          end
        end

        # @return [String]
        def to_json(*) = JSON.generate(wire)
      end

      class Turn
        # @param data [Hash] a turn as the wire carries it
        # @return [OpenLanes::Live::Interview::Turn]
        # @raise [OpenLanes::Live::Interview::Invalid]
        def self.parse(data)
          data = data.transform_keys(&:to_s)
          words = %w[id from kind text].to_h { [it.to_sym, data[it].to_s] }
          new(**words,
            at:      data["at"] ? Time.iso8601(data["at"]) : Time.now,
            options: data["options"]&.map { it.transform_keys(&:to_sym) },
            answer:  data["answer"])
        rescue ArgumentError => e
          raise Invalid, "not a turn: #{e.message}"
        end

        # @param turn [OpenLanes::Live::Interview::Turn]
        # @return [void]
        # @raise [OpenLanes::Live::Interview::Invalid] naming what is wrong
        def self.check(turn)
          check_base(turn)
          check_label(turn) unless turn.kind == "text"
          check_options(turn.options) if turn.kind == "question"
          raise Invalid, "a decision needs an answer" if turn.kind == "decision" && turn.answer.to_s.strip.empty?
        end

        # @return [void]
        def self.check_base(turn)
          raise Invalid, "unknown speaker #{turn.from.inspect}" unless SPEAKERS.include?(turn.from)
          raise Invalid, "unknown kind #{turn.kind.inspect}; known: #{KINDS.join(", ")}" unless KINDS.include?(turn.kind)
          raise Invalid, "only the unblocker asks or decides" if turn.from == "you" && turn.kind != "text"

          check_size(turn.text)
        end

        # @return [void]
        def self.check_size(text)
          raise Invalid, "a turn needs text" if text.strip.empty?
          raise Invalid, "a turn is at most #{LIMIT} characters" if text.length > LIMIT
        end

        # The unblocker's own words only. A decision's `answer` carries the
        # person's words, which may say "B2" and are theirs to say (F3).
        #
        # @return [void]
        def self.check_label(turn)
          words = [turn.text, *Array(turn.options).map { it[:label] }].compact.join(" ")
          label = words[LABEL] and raise Invalid, "#{label} is a bare label; say what it is in words"
        end

        # @return [void]
        def self.check_options(options)
          options = Array(options)
          raise Invalid, "a question needs 2 to 5 options" unless (2..5).cover?(options.size)
          raise Invalid, "every option needs a label" if options.any? { it[:label].to_s.strip.empty? }
          raise Invalid, "a question marks exactly one option recommended" unless options.one? { it[:recommended] == true }
        end
      end
    end
  end
end
