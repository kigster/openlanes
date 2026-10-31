# frozen_string_literal: true

module OpenLanes
  module Setup
    # Reads the description a person typed and preselects whichever answers it
    # settles, through `inquirex-llm`. The person still sees and can change them.
    #
    # It only ever drops: a blank, a nil, or a value outside a closed list is left
    # out, so no placeholder answer can reach the config (M16 forbids them, and
    # `Inquirex::LLM::NullAdapter` invents them).
    class Extractor
      # What the model reads with the description. The closed lists reach it
      # through the schema, which the form's own questions supply.
      PROMPT = <<~PROMPT
        Read the description of a software project and fill in only what it states or clearly implies.
        Leave a field null when the description does not say. Never guess.
        Fields starting with target_ describe what the person wants the project to use.
        merge_by: "human" when a person merges pull requests, "auto" when they merge on a passing review.
      PROMPT

      # The answers extraction may preselect, and what each may hold.
      FIELDS = Architecture::ATTRIBUTES.to_h { [:"target_#{it.name}", it] }.freeze

      # The form's other closed answers.
      VOCABULARIES = { merge_by: Config::MERGERS, desired_codebase_quality: Config::QUALITIES }.freeze

      # @param route [OpenLanes::Setup::Extraction::Route, nil] nil: nothing can read it
      # @return [OpenLanes::Setup::Extractor, nil]
      def self.on(route) = route && new(label: route.label, adapter: route.adapter)

      # @return [String] where a description is sent, said before it is asked for
      attr_reader :label

      # @param label [String]
      # @param adapter [#call] builds the adapter, which answers `call(node, answers)`
      def initialize(label:, adapter:)
        @label = label
        @adapter = adapter
      end

      # @param node [Inquirex::LLM::Node] the form's extract step
      # @param description [String]
      # @return [Hash{Symbol => Object}] only the answered fields; empty on any adapter error
      def call(node, description)
        return {} if description.to_s.strip.empty?

        result = @adapter.call.call(node, { description: description.to_s })
        answered((FIELDS.keys + VOCABULARIES.keys).to_h { [it, clean(it, result[it])] })
      rescue StandardError => e
        # The class alone: an adapter's message can quote the description or the key.
        UI.log("extraction: no answers (#{e.class})")
        {}
      end

      private

      # @return [Hash{Symbol => Object}]
      def answered(fields) = fields.reject { |_, value| value.nil? || value == [] }

      # @return [Object, nil]
      def clean(field, value)
        return member(value, VOCABULARIES.fetch(field)) if VOCABULARIES.key?(field)

        attribute = FIELDS.fetch(field)
        case attribute.kind
        when :one then member(value, attribute.values)
        when :paths then words(value).join(", ").then { it.empty? ? nil : it }
        else words(value).filter_map { member(it, attribute.values) }
        end
      end

      # @return [Array<String>]
      def words(value) = Array(value).grep(String).map(&:strip).reject(&:empty?)

      # @return [String, nil]
      def member(value, allowed)
        word = value.to_s.strip.downcase.to_sym
        word.to_s if allowed.include?(word)
      end
    end
  end
end
