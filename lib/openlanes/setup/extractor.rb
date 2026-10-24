# frozen_string_literal: true

module OpenLanes
  module Setup
    # Reads "Describe the app you want to build" and answers whichever
    # interview questions the description already settles, through
    # `inquirex-llm`. The interview skips those and asks the rest.
    #
    # It only ever drops: a blank, a nil, or a value outside a closed
    # vocabulary is left out, so no placeholder answer can reach the config
    # (M16 forbids them, and `Inquirex::LLM::NullAdapter` invents them).
    #
    # A seam, like {Live::ChoiceJudge}: specs hand it an adapter double, and
    # nothing in the suite reaches the network.
    class Extractor
      # Used when OPENLANES_EXTRACTION_MODEL names none. Anthropic's id; an
      # OpenAI key takes the adapter's own default instead.
      DEFAULT_MODEL = "claude-sonnet-5-5"

      # What the model reads with the description.
      PROMPT = <<~PROMPT
        Read the description of a software project and fill in only what it states or clearly implies.
        Leave a field empty when the description does not say. Never guess.
        merge_by: "human" when a person merges pull requests, "auto" when they merge on a passing review.
        desired_codebase_quality: one of high, mvp.
        language, front_end, persistence, caching, logins, deployment, domain: short lower-case names.
        frameworks: a list of framework names.
      PROMPT

      # The questions extraction may answer.
      FIELDS = (%i[merge_by desired_codebase_quality] + Config::STACK_FIELDS - %i[from to]).freeze

      # Field → its closed vocabulary, for the fields that have one.
      VOCABULARIES = {
        merge_by:                 Config::MERGERS,
        desired_codebase_quality: Config::QUALITIES
      }.freeze

      class << self
        # An extractor on the first key present, or nil with neither, so the
        # caller can say so once and ask every question.
        #
        # @param env [#[]]
        # @return [OpenLanes::Setup::Extractor, nil]
        def from_env(env = ENV)
          model = env["OPENLANES_EXTRACTION_MODEL"].to_s.strip
          anthropic = env["ANTHROPIC_API_KEY"].to_s.strip
          openai = env["OPENAI_API_KEY"].to_s.strip
          if !anthropic.empty?
            new(provider: :anthropic, api_key: anthropic, model: model.empty? ? DEFAULT_MODEL : model)
          elsif !openai.empty?
            new(provider: :openai, api_key: openai, model: model.empty? ? nil : model)
          end
        end
      end

      # @return [Symbol] :anthropic or :openai
      attr_reader :provider

      # @param provider [Symbol] :anthropic or :openai
      # @param api_key [String, nil] only read to build the default adapter
      # @param model [String, nil]
      # @param adapter [#call, nil] answers `call(node, answers)` with a
      #   Hash-like result; built on first use, so `inquirex` loads only when
      #   something is extracted
      def initialize(provider: :anthropic, api_key: nil, model: DEFAULT_MODEL, adapter: nil)
        @provider = provider
        @api_key = api_key
        @model = model
        @adapter = adapter
      end

      # @param description [String]
      # @return [Hash{Symbol => Object}] only the answered fields; empty on any adapter error
      def call(description)
        return {} if description.to_s.strip.empty?

        result = adapter.call(node, { description: description.to_s })
        FIELDS.each_with_object({}) do |field, answers|
          value = clean(field, result[field])
          answers[field] = value unless value.nil?
        end
      rescue StandardError => e
        UI.log("extraction: no answers (#{e.class})")
        {}
      end

      private

      # @return [Object, nil]
      def clean(field, value)
        return list(value) if Config::STACK_LISTS.include?(field)
        return nil unless value.is_a?(String) || value.is_a?(Symbol)

        text = value.to_s.strip
        return nil if text.empty?

        vocabulary = VOCABULARIES[field]
        return text unless vocabulary

        word = text.downcase.to_sym
        vocabulary.include?(word) ? word : nil
      end

      # @return [Array<String>, nil]
      def list(value)
        names = Array(value).grep(String).map(&:strip).reject(&:empty?)
        names.empty? ? nil : names
      end

      def adapter
        @adapter ||= begin
          require "inquirex-llm"
          klass = provider == :openai ? Inquirex::LLM::OpenAIAdapter : Inquirex::LLM::AnthropicAdapter
          klass.new(api_key: @api_key, model: @model)
        end
      end

      def node
        require "inquirex-llm"
        schema = FIELDS.to_h { [it, Config::STACK_LISTS.include?(it) ? :array : :string] }
        Inquirex::LLM::Node.new(id: :stack,
          verb: :extract,
          prompt: PROMPT,
          schema: Inquirex::LLM::Schema.new(**schema),
          from_steps: [:description])
      end
    end
  end
end
