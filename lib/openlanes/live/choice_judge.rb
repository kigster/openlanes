# frozen_string_literal: true

require "digest"

module OpenLanes
  module Live
    # A second opinion on {Plans::Choices}: does this message ask its reader
    # to choose one of the options it lists? Asked of Jev, TypeSafe's System
    # One model, through `inquirex-llm`'s `JevAdapter`, as one boolean.
    #
    # The parser cannot tell "Done so far: 1. … 2. …" from a numbered choice;
    # Jev can. Its answer only ever narrows: `false` takes the buttons away and
    # leaves the text box, `true` keeps them, and `nil` (no answer, an error, a
    # timeout, an answer too unsure to count) leaves the parser's verdict as it
    # was. A missing key therefore costs nothing but the second opinion.
    #
    # The snapshot is rebuilt every time the board moves, so every answer is
    # kept, in this process, by the SHA256 of the text: one request per
    # distinct question, ever. A request still in flight when {#call} gives up
    # waiting goes on in its thread, and the next snapshot finds its answer.
    #
    # A seam, like {Vcs::GitHub} and {Linear::API}: the suite sets
    # {Live.choice_judge} to nil, and examples about the judge hand it an
    # adapter double, so nothing in the tests reaches TypeSafe.
    class ChoiceJudge
      # What Jev reads with the message. Its boolean question is whether
      # `asks_to_choose` is true according to the message.
      PROMPT = <<~PROMPT
        The message below was written by a software agent to a person, who answers it in a web page.
        `asks_to_choose` is true when the message asks the person to pick one of the options it lists
        (lettered or numbered alternatives, or a plain yes/no question), and false when the list is
        something else: steps already done, findings, a plan, or a question that wants a written answer.
      PROMPT

      # How long a snapshot waits for an answer it does not have yet.
      TIMEOUT = 3.0

      # Below this Jev is guessing, and the parser's verdict stands.
      MIN_CONFIDENCE = 0.6

      # The schema field Jev answers.
      FIELD = :asks_to_choose

      # A judge when TYPESAFE_API_KEY is set, nil otherwise.
      #
      # @param env [#[]]
      # @return [OpenLanes::Live::ChoiceJudge, nil]
      def self.from_env(env = ENV)
        key = env["TYPESAFE_API_KEY"].to_s.strip
        key.empty? ? nil : new(api_key: key)
      end

      # @param api_key [String, nil] TypeSafe's; only read to build the default adapter
      # @param adapter [#call, nil] answers `call(node, answers)` with a Hash
      #   holding {FIELD}, as `Inquirex::LLM::JevAdapter` does; built on first
      #   use when nil, so a process that never judges never loads inquirex
      # @param timeout [Float] seconds {#call} waits for an answer it lacks
      def initialize(api_key: nil, adapter: nil, timeout: TIMEOUT)
        @api_key = api_key
        @adapter = adapter
        @timeout = timeout
        @answers = {}
        @mutex = Mutex.new
      end

      # @param text [String] the question, as the person would read it
      # @return [Boolean, nil] whether it asks to choose; nil when Jev has not
      #   said, or could not
      def call(text)
        key = Digest::SHA256.hexdigest(text.to_s)
        asking = @mutex.synchronize { @answers[key] ||= ask(text.to_s) }
        asking.join(@timeout) ? asking.value : nil
      end

      private

      # @return [Thread] whose value is true, false or nil
      def ask(text)
        Thread.new do
          Thread.current.report_on_exception = false
          adapter.call(node, { message: text })[FIELD]
        rescue StandardError => e
          UI.log("choice judge: no verdict (#{e.class})")
          nil
        end
      end

      def adapter
        @mutex.synchronize do
          @adapter ||= begin
            require "inquirex-llm"
            Inquirex::LLM::JevAdapter.new(api_key: @api_key, min_confidence: MIN_CONFIDENCE)
          end
        end
      end

      def node
        @node ||= begin
          require "inquirex-llm"
          Inquirex::LLM::Node.new(id: :choice,
            verb: :extract,
            prompt: PROMPT,
            schema: Inquirex::LLM::Schema.new(FIELD => :boolean),
            from_steps: [:message])
        end
      end
    end
  end
end
