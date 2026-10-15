# frozen_string_literal: true

module OpenLanes
  module Live
    # Rewrites a question an agent wrote as prose into D3's shape (D9): a
    # short context paragraph and lettered options, exactly one recommended.
    # The page draws a button per option and a text box under them, so a
    # person can answer with one click instead of composing a reply to a
    # paragraph.
    #
    # One call to a small model on OpenRouter, through `inquirex-llm`'s
    # `OpenRouterAdapter`, which asks for a JSON object and checks that both
    # fields came back. What the model returns is not trusted to be D3: it is
    # cleaned, written out with {Plans::Choices.write}, and read back with
    # {Plans::Choices.parse}, and anything that does not survive the trip is
    # {Invalid}.
    #
    # It neither reads nor writes `blocked.md`; {Engine::Conversions} does,
    # so this stays a function of text, and a seam: the suite sets
    # {Live.choice_converter} to nil, and examples about it hand it an
    # adapter double, so nothing in the tests reaches OpenRouter.
    class ChoiceConverter
      # Small and quick, and listed by OpenRouter and by inquirex-llm's own
      # catalogue (`Models::OPENROUTER_ALIASES[:claude_haiku]`).
      # `questions.model` in `.openlanes.yml` replaces it.
      DEFAULT_MODEL = "anthropic/claude-haiku-5.5"

      # What the model reads with the question.
      PROMPT = <<~PROMPT
        A software agent stopped and wrote the question below for a person. The person answers it in a
        web page that shows one button per option and a free-text box under them. Rewrite the question as
        multiple choice:

        - `context`: one short paragraph with what the person needs to know to choose. Keep every fact,
          number and name that matters; drop repetition. Do not repeat the heading.
        - `options`: an array of 2 to 5 objects `{"label": String, "recommended": Boolean}`, each a distinct
          answer the question already implies, written as one short line in the agent's own terms.
          Exactly one has `"recommended": true`: the one the question itself prefers, or, if it prefers
          none, the safest one.

        Never change what is being asked, never add facts the question does not state, never answer it,
        and never add an option for "something else" or "type something instead": the page has a text box.
      PROMPT

      # What the model answered could not be made into a D3 question.
      class Invalid < Error; end

      # @!attribute [r] body
      #   @return [String] the question's new body, D3-shaped Markdown
      # @!attribute [r] count
      #   @return [Integer] how many options it offers
      # @!attribute [r] model
      #   @return [String] the model that wrote it
      Result = Data.define(:body, :count, :model)

      # A converter when OPENROUTER_API_KEY is set, nil otherwise.
      #
      # @param env [#[]]
      # @param config [OpenLanes::Config]
      # @return [OpenLanes::Live::ChoiceConverter, nil]
      def self.from_env(env = ENV, config: Config.current)
        key = env["OPENROUTER_API_KEY"].to_s.strip
        key.empty? ? nil : new(api_key: key, model: config.questions_model || DEFAULT_MODEL)
      end

      # The model's answer, cleaned and written in D3's shape.
      #
      # @param output [Hash] `context` and `options`, as the adapter parsed them
      # @return [String] the new body
      # @raise [Invalid] when it cannot be one
      def self.render(output)
        output = output.to_h.transform_keys(&:to_sym)
        context = output[:context].to_s.strip
        raise Invalid, "no context" if context.empty?
        # A heading inside the body would end the question there, and a
        # `Bn` or `An` line would start another one.
        if [Plans::BlockedFile::HEADING, Plans::OPEN_BLOCK, Plans::ANSWER_BLOCK].any? { context.match?(it) }
          raise Invalid, "the context holds a heading"
        end

        options = Array(output[:options]).map { option(it) }
                                         .reject { |label, _| label.match?(Plans::Choices::SOMETHING_ELSE) }
        raise Invalid, "#{options.size} option#{"s" unless options.size == 1}, not 2 or more" if options.size < 2

        recommended = options.each_index.select { options[it].last }
        raise Invalid, "#{recommended.size} options recommended, not one" unless recommended.size == 1

        body = Plans::Choices.write(context:, labels: options.map(&:first), recommended: recommended.first)
        back = Plans::Choices.parse(body)
        raise Invalid, "the rewrite does not read back as #{options.size} choices" unless back&.options&.size == options.size

        body
      end

      # One option as a label on one line and whether it is recommended; a
      # recommendation the model wrote into the label is taken out of it, since
      # the flag already says so.
      #
      # @param raw [Hash, Object]
      # @return [Array(String, Boolean)]
      # @raise [Invalid]
      def self.option(raw)
        raise Invalid, "an option is not an object" unless raw.is_a?(Hash)

        raw = raw.transform_keys(&:to_sym)
        label = raw[:label].to_s.gsub(/\s+/, " ").sub(Plans::Choices::RECOMMENDED, " ").strip
        raise Invalid, "an option has no label" if label.empty?

        [label, [true, "true"].include?(raw[:recommended])]
      end
      private_class_method :option

      # @param api_key [String, nil] OpenRouter's; only read to build the default adapter
      # @param model [String] an OpenRouter model id
      # @param adapter [#call, nil] answers `call(node, answers)` with a Hash
      #   holding `context` and `options`, as `Inquirex::LLM::OpenRouterAdapter`
      #   does; built on first use when nil, so a process that never converts
      #   never loads inquirex
      def initialize(api_key: nil, model: DEFAULT_MODEL, adapter: nil)
        @api_key = api_key
        @model = model
        @adapter = adapter
        @mutex = Mutex.new
      end

      # @return [String]
      attr_reader :model

      # Blocks for as long as the request takes (the adapter gives up after
      # 30 seconds without an answer), so the engine calls it on a thread.
      #
      # @param heading [String] the question's heading, for context; it is kept
      # @param body [String] the question as the agent wrote it
      # @return [OpenLanes::Live::ChoiceConverter::Result]
      # @raise [Invalid] when the answer is not a D3 question
      # @raise [StandardError] whatever the adapter raises: no network, a 4xx, bad JSON
      def call(heading:, body:)
        output = adapter.call(node, { heading: heading.to_s, question: body.to_s })
        written = self.class.render(output)
        Result.new(body: written, count: Plans::Choices.parse(written).options.size, model:)
      end

      private

      def adapter
        @mutex.synchronize do
          @adapter ||= begin
            require "inquirex-llm"
            Inquirex::LLM::OpenRouterAdapter.new(api_key: @api_key, model:)
          end
        end
      end

      def node
        @node ||= begin
          require "inquirex-llm"
          Inquirex::LLM::Node.new(id: :choices,
            verb: :extract,
            prompt: PROMPT,
            schema: Inquirex::LLM::Schema.new(context: :string, options: :array),
            from_steps: %i[heading question])
        end
      end
    end
  end
end
