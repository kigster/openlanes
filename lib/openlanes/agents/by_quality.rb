# frozen_string_literal: true

module OpenLanes
  module Agents
    # The model and effort an agent runs on for each `desired_codebase_quality:`,
    # from its `by_quality:` frontmatter, e.g.
    # `by_quality: { high: { model: fable } }`.
    #
    # It lives in the agent's definition, beside `small_diff:`, because which
    # model an agent runs on is a routing fact, and those belong in
    # `agents/*.md`. Read by {Profile.resolve}, below `run --model`, spec.md
    # and `sizing:`, and above `small_diff:`: a project that asked for high
    # quality wants its reviewer on the stronger model however small the
    # diff. A `model` or `effort` in `.openlanes/config.yml` `agents:` takes
    # that key back ({Overrides#apply}).
    #
    # Model and effort are chosen separately, so an entry naming only a
    # model keeps whatever effort would otherwise apply.
    #
    # @!attribute [r] settings
    #   @return [Hash{Symbol => Hash{Symbol => String}}] quality => `{model:, effort:}`
    ByQuality = Data.define(:settings) do
      # @param quality [Symbol, nil] `desired_codebase_quality:`, nil when unset
      # @return [Hash{Symbol => String}] `{model:, effort:}`, empty for a
      #   quality it names nothing for
      def for(quality) = settings.fetch(quality, {})

      # @param keys [Array<Symbol>] keys something more specific has set
      # @return [ByQuality] with those keys dropped from every quality
      def without(keys) = with(settings: settings.transform_values { it.except(*keys) })
    end

    class ByQuality
      class << self
        # @param value [Hash, nil] the frontmatter's `by_quality:`
        # @param path [String] for the error message
        # @return [OpenLanes::Agents::ByQuality, nil]
        # @raise [OpenLanes::Error] on an unknown quality, a value that is not
        #   a mapping, or an unknown effort
        def parse(value, path)
          return nil if value.nil?
          raise OpenLanes::Error, "#{File.basename(path)}: by_quality must be a mapping, e.g. #{EXAMPLE}" unless value.is_a?(Hash)

          new(settings: value.to_h { |quality, entry| [quality(quality, path), entry(entry, path)] })
        end

        private

        EXAMPLE = "`by_quality: { high: { model: fable } }`"
        KEYS = %w[model effort].freeze
        private_constant :EXAMPLE, :KEYS

        # @return [Symbol]
        def quality(name, path)
          key = name.to_s.strip.downcase.to_sym
          return key if Config::QUALITIES.include?(key)

          raise OpenLanes::Error, "#{File.basename(path)}: by_quality #{name.to_s.inspect} is not one of #{Config::QUALITIES.join(", ")}"
        end

        # @return [Hash{Symbol => String}]
        def entry(value, path)
          refuse(path, "values must be mappings, e.g. #{EXAMPLE}") unless value.is_a?(Hash)

          settings = value.transform_keys(&:to_s)
          unknown = settings.keys - KEYS
          refuse(path, "knows only #{KEYS.join(" and ")}, not #{unknown.join(", ")}") unless unknown.empty?
          { model: model(settings, path), effort: effort(settings["effort"], path) }.compact
        end

        # @return [String, nil]
        def model(settings, path)
          value = settings["model"]
          return value unless settings.key?("model") && !(value.is_a?(String) && !value.strip.empty?)

          refuse(path, "model must be a model name, not #{value.inspect}")
        end

        # @return [String, nil]
        def effort(value, path)
          return nil if value.nil?
          return value.to_s if Adapters.effort?(value.to_s)

          refuse(path, "effort #{value.to_s.inspect} is not one of #{Adapters::EFFORTS.join(", ")}")
        end

        # @raise [OpenLanes::Error]
        def refuse(path, why) = raise(OpenLanes::Error, "#{File.basename(path)}: by_quality #{why}")
      end
    end
  end
end
