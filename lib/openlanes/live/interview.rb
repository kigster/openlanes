# frozen_string_literal: true

require "digest"
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
    # The stream's own entry id is each turn's place in the conversation
    # ({Turn#seq}), and the page draws by it. A turn's time is whole seconds
    # and its id is random, so a reply of two turns sorted by those came out
    # in either order, and half the time the buttons were not drawn (issue 252).
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

      # Times one reply is written again because the person said more while
      # it was being written. Bounded, so a person who keeps typing cannot
      # keep a model running for as long as they type.
      ATTEMPTS = 3

      # Said when a turn of the person's slipped in beside a reply already
      # stored: what stands above it never read that turn, so it must not
      # stay the newest thing said while the next reply is written.
      MORE = "You wrote more while I was answering. Give me a moment to read it."

      # Said when {ATTEMPTS} replies in a row were overtaken.
      LATE = "You kept writing while I was answering, so I have not answered yet. " \
             "Send one more message when you are done and I will read all of it."

      # What names the question a conversation is about: its heading and
      # body as `blocked.md` asks it now. `blocked.md` numbers from B1 every
      # time a plan blocks, so the number alone let a decision reached on
      # one question be confirmed as the answer to the next (issue 252).
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param number [Integer, String] the question's number
      # @return [String, nil] nil when the plan has no such question open and unanswered
      def self.topic(subject, number)
        question = Lifecycle::Unblocker.questions(subject).find { it.number == number.to_i && !it.answered } or return
        body = Plans::BlockedFile.bodies(subject.read("blocked.md").to_s)[question.number]
        Digest::SHA256.hexdigest("#{question.heading}\n#{body}")
      end

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

      # @return [Array<OpenLanes::Live::Interview::Turn>] oldest first, each with its {Turn#seq}
      def history = @store.xrange(key, count: LENGTH).map { Turn.parse(JSON.parse(it.fields["json"])).with(seq: it.id) }

      # Store +turn+, and publish it to the open pages as `event: interview`.
      #
      # @param turn [OpenLanes::Live::Interview::Turn]
      # @return [OpenLanes::Live::Interview::Turn] the turn with its place in the conversation
      def say(turn)
        said = turn.with(seq: EventBus.for(@store).append(key, { json: turn.to_json }, maxlen: LENGTH))
        Feed.new(store: @store, keys: @keys).append(plan:, number:, turn: said)
        News.publish(store: @store, keys: @keys, kind: "interview")
        said
      end

      # Keep the conversation to the question as it is asked now. One held
      # about another question, or about none that anyone recorded, is
      # forgotten first: it was answered on the card or drained, and its
      # decision is not an answer to this one.
      #
      # @param topic [String] {Interview.topic}
      # @return [void]
      def about(topic)
        known = @store.get(topic_key)
        return if known == topic

        close if known || !history.empty?
        @store.set(topic_key, topic)
      end

      # How long one reply may hold the interview before another may start,
      # in seconds: longer than a slow model's turn, short enough that a
      # crashed server does not silence the interview for good.
      BUSY = 600

      # Store what +responder+ says next, when the person is owed a turn: the
      # interview is empty, or the person spoke last. One reply runs at a
      # time per question (F2): a second caller, say a reload while the
      # opening question is still being written, leaves a note and returns,
      # and the one running looks again once it is done.
      #
      # A reply answers what the person had said when it was begun. When
      # they say more before it is stored, it is discarded and written
      # again, at most {ATTEMPTS} times: stored, it would be the newest turn,
      # the person would be owed nothing, and a decision that never read
      # their correction would be theirs to confirm (issue 252).
      #
      # A responder that fails is answered for in plain words, never as a
      # refusal of what the person said, so the page shows why it went quiet
      # and the buttons stay usable.
      #
      # @param responder [#call] given this interview, returns its next {Turn}s
      # @return [Array<OpenLanes::Live::Interview::Turn>] what was stored
      def reply(responder)
        said = []
        while (turns = held { |token| owed? ? answer(responder, token) : [] })
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

      # The decision turn +id+, when it is the newest thing said. Anything
      # said after a decision, by either side, means it no longer stands.
      #
      # @param id [String]
      # @return [OpenLanes::Live::Interview::Turn, nil]
      def decision(id)
        last = history.last
        last if last&.id == id.to_s && last.kind == "decision"
      end

      # Forget the conversation: the question is answered, so it is over.
      #
      # @return [void]
      def close = @store.del(key, busy_key, again_key, topic_key)

      # @return [Hash] `{turns: [InterviewTurn]}`, as the API serves it
      def wire = { turns: history.map(&:wire) }

      private

      # Run the block holding the interview, or leave a note for the holder.
      #
      # @yieldparam token [String] what the hold is kept under, to extend it
      # @return [Object, nil] the block's value, nil when another reply holds it
      def held
        @store.set(again_key, "1", ex: BUSY)
        token = SecureRandom.hex(8)
        return unless @store.set(busy_key, token, ex: BUSY, nx: true)

        begin
          @store.del(again_key)
          yield token
        ensure
          @store.compare_and_delete(busy_key, token)
        end
      end

      # @return [Array<OpenLanes::Live::Interview::Turn>] what was stored
      def answer(responder, token)
        said = []
        ATTEMPTS.times do
          # Each attempt is a model run of its own, so each gets the whole hold.
          @store.compare_and_expire(busy_key, token, BUSY)
          return said if attempt(responder, said)
        end
        said << say(words(LATE))
      end

      # One reply, stored only when it answers everything the person has
      # said. The second look, after storing, is for a turn that arrived
      # between the first look and the write.
      #
      # @param said [Array<OpenLanes::Live::Interview::Turn>] collects what is stored
      # @return [Boolean] false when the person said more, and it is to be written again
      def attempt(responder, said)
        read = marker
        turns = compose(responder)
        return true unless marker.first == read.first
        return false unless marker == read

        said.concat(turns.map { say(it) })
        return true if marker == read

        said << say(words(MORE))
        false
      end

      # What a reply is written against: the question the conversation is
      # about, and the newest thing the person said. The first changing
      # means the conversation was closed under the reply, which is then
      # dropped; the second, that the reply answers too little.
      #
      # @return [Array(String, String)] the topic and a {Turn#seq}, either nil
      def marker = [@store.get(topic_key), history.rfind { it.from == "you" }&.seq]

      # A responder that fails is answered for in plain words.
      #
      # @return [Array<OpenLanes::Live::Interview::Turn>] not stored yet
      def compose(responder)
        responder.call(self)
      rescue StandardError => e
        [words("The interview could not go on (#{e.message.lines.first.to_s.strip}). The answer buttons still work.")]
      end

      # @return [OpenLanes::Live::Interview::Turn] the unblocker's own words, outside any reply
      def words(text) = Turn.new(id: next_id, from: "unblocker", kind: "text", text: text[0, LIMIT])

      # @return [String]
      def key = @keys.interview(@plan, @number)

      # @return [String] held while a reply is being written
      def busy_key = "#{key}:busy"

      # @return [String] set by a caller that found a reply under way
      def again_key = "#{key}:again"

      # @return [String] holds the {Interview.topic} the conversation is about
      def topic_key = "#{key}:topic"
    end

    class Interview
      # One thing said in the interview: `InterviewTurn` in `types.ts`.
      #
      # +seq+ is the turn's place in the conversation, the id its stream
      # entry was given: nil until {Interview#say} has stored it, and never
      # stored inside the turn, since the entry already carries it.
      Turn = Data.define(:id, :from, :kind, :text, :at, :options, :answer, :seq) do
        def initialize(**given)
          super(at: Time.now, options: nil, answer: nil, seq: nil, **given)
          Turn.check(self)
        end

        # @return [Hash] as the wire carries it
        def wire
          { id:, from:, kind:, text:, at: at.utc.iso8601 }.tap do |hash|
            hash[:seq] = seq if seq
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
          raise Invalid, "not a turn: #{data.class} where an object belongs" unless data.is_a?(Hash)

          data = data.transform_keys(&:to_s)
          words = %w[id from kind text].to_h { [it.to_sym, data[it].to_s] }
          new(**words,
            at:      time_in(data["at"]),
            options: options_in(data["options"]),
            answer:  data["answer"]&.to_s)
        rescue ArgumentError => e
          raise Invalid, "not a turn: #{e.message}"
        end

        # @param raw [Object] what the wire carries as `at`
        # @return [Time] now, for a turn that names no time
        def self.time_in(raw) = raw ? Time.iso8601(raw.to_s) : Time.now

        # A model writes `options` as it likes: a list of words, one string,
        # a number. Each is output that cannot be drawn, and is said so here
        # rather than left to raise NoMethodError a line later, which reached
        # the page as Ruby's own words (issue 252).
        #
        # @param raw [Object] what the wire carries as `options`
        # @return [Array<Hash{Symbol => Object}>, nil]
        # @raise [OpenLanes::Live::Interview::Invalid]
        def self.options_in(raw)
          return if raw.nil?
          raise Invalid, "options must be a list of {label, recommended} objects" unless raw.is_a?(Array) && raw.all?(Hash)

          raw.map { it.transform_keys(&:to_sym) }
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
