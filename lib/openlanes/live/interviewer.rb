# frozen_string_literal: true

module OpenLanes
  module Live
    # Grills a new idea before its spec.md is written (M6): the questions the
    # agents downstream would otherwise block to ask, each as a short context
    # paragraph and lettered options with exactly one recommended. The page
    # asks them one at a time, and the answers reach {Commands#create_plans}
    # as `payload.decisions`, which writes them into the spec.
    #
    # One call to a small model on OpenRouter, as {ChoiceConverter} makes,
    # and every question is checked the same way: written with
    # {Plans::Choices.write} and read back with {Plans::Choices.parse}. A
    # question that does not survive the trip is dropped, not the interview:
    # four good questions are worth asking without the fifth.
    #
    # A seam: the suite sets {Live.interviewer} to nil, and examples about it
    # hand it an adapter double, so nothing in the tests reaches OpenRouter.
    class Interviewer
      # The most questions one idea is asked. A person is interviewed while
      # they wait, so the list stays short (M0).
      LIMIT = 5

      # What the model reads with the idea.
      PROMPT = <<~PROMPT.freeze
        A person described a software feature they want built. Agents will turn it into a spec, a plan and
        code without being able to ask anything, so interview the person now. Return `questions`: an array
        of at most #{LIMIT} objects, the decisions that most change what gets built and that the idea leaves open.
        Ask nothing the idea already answers. Each object is:

        - `context`: one short paragraph saying what must be decided and why it matters.
        - `options`: an array of 2 to 5 objects `{"label": String, "recommended": Boolean}`, each a distinct
          answer on one short line. Exactly one has `"recommended": true`: the one you would choose.

        Never add an option for "something else" or "type something instead": the page has a text box.
        An idea that leaves nothing open gets an empty array.
      PROMPT

      # One question, ready for the page.
      #
      # @!attribute [r] context
      #   @return [String]
      # @!attribute [r] options
      #   @return [Array<String>] labels, in order
      # @!attribute [r] recommended
      #   @return [Integer] the index of the recommended option
      Question = Data.define(:context, :options, :recommended) do
        # @return [Hash] as `POST /api/interview` sends it
        def wire = { context:, options:, recommended: }
      end

      # An interviewer when OPENROUTER_API_KEY is set, nil otherwise.
      #
      # @param env [#[]]
      # @param config [OpenLanes::Config]
      # @return [OpenLanes::Live::Interviewer, nil]
      def self.from_env(env = ENV, config: Config.current)
        key = env["OPENROUTER_API_KEY"].to_s.strip
        key.empty? ? nil : new(api_key: key, model: config.questions_model || ChoiceConverter::DEFAULT_MODEL)
      end

      # The model's questions, each cleaned the way {ChoiceConverter.render}
      # cleans one, keeping those that survive.
      #
      # @param output [Hash] `questions`, as the adapter parsed it
      # @return [Array<OpenLanes::Live::Interviewer::Question>] at most {LIMIT}
      def self.render(output)
        output = output.to_h.transform_keys(&:to_sym)
        Array(output[:questions]).filter_map { question(it) }.first(LIMIT)
      end

      # @param raw [Object]
      # @return [OpenLanes::Live::Interviewer::Question, nil]
      def self.question(raw)
        return unless raw.is_a?(Hash)

        body = ChoiceConverter.render(raw)
        choices = Plans::Choices.parse(body)
        Question.new(context: choices.context,
          options: choices.options.map(&:label),
          recommended: choices.options.index(&:recommended))
      rescue ChoiceConverter::Invalid
        nil
      end
      private_class_method :question

      # @param api_key [String, nil] OpenRouter's; only read to build the default adapter
      # @param model [String] an OpenRouter model id
      # @param adapter [#call, nil] answers `call(node, answers)` with a Hash
      #   holding `questions`; built on first use when nil
      def initialize(api_key: nil, model: ChoiceConverter::DEFAULT_MODEL, adapter: nil)
        @api_key = api_key
        @model = model
        @adapter = adapter
        @mutex = Mutex.new
      end

      # @return [String]
      attr_reader :model

      # Blocks for as long as the request takes.
      #
      # @param idea [String] Markdown, as the idea dialog sends it
      # @return [Array<OpenLanes::Live::Interviewer::Question>]
      # @raise [StandardError] whatever the adapter raises: no network, a 4xx, bad JSON
      def call(idea:) = self.class.render(adapter.call(node, { idea: idea.to_s }))

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
          Inquirex::LLM::Node.new(id: :interview,
            verb: :extract,
            prompt: PROMPT,
            schema: Inquirex::LLM::Schema.new(questions: :array),
            from_steps: %i[idea])
        end
      end
    end
  end
end
