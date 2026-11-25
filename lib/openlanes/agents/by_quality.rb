# frozen_string_literal: true

module OpenLanes
  module Agents
    # The model and effort an agent runs on for each `desired_codebase_quality:`,
    # from its `by_quality:` frontmatter, e.g.
    # `by_quality: { high: { model: fable } }`.
    #
    # It lives in the agent's definition, beside `small_diff:`, because which
    # model an agent runs on is a routing fact, and those belong in
    # `agents/*.md`. Read by {Profile.resolve}, below every override a person
    # typed and above `small_diff:`: a project that asked for high quality
    # wants its reviewer on the stronger model however small the diff.
    #
    # @!attribute [r] settings
    #   @return [Hash{Symbol => Hash{Symbol => String}}] quality => `{model:, effort:}`
    ByQuality = Data.define(:settings) do
      # @param quality [Symbol, nil] `desired_codebase_quality:`, nil when unset
      # @return [Hash{Symbol => String}] `{model:, effort:}`, empty for a
      #   quality it names nothing for
      def for(quality) = settings.fetch(quality, {})
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
        private_constant :EXAMPLE

        # @return [Symbol]
        def quality(name, path)
          key = name.to_s.strip.downcase.to_sym
          return key if Config::QUALITIES.include?(key)

          raise OpenLanes::Error, "#{File.basename(path)}: by_quality #{name.to_s.inspect} is not one of #{Config::QUALITIES.join(", ")}"
        end

        # @return [Hash{Symbol => String}]
        def entry(value, path)
          raise OpenLanes::Error, "#{File.basename(path)}: by_quality values must be mappings, e.g. #{EXAMPLE}" unless value.is_a?(Hash)

          settings = value.transform_keys(&:to_s)
          effort = settings["effort"]&.to_s
          if effort && !Adapters.effort?(effort)
            raise OpenLanes::Error, "#{File.basename(path)}: by_quality effort #{effort.inspect} is not one of #{Adapters::EFFORTS.join(", ")}"
          end

          { model: settings["model"]&.to_s, effort: }.compact
        end
      end
    end
  end
end
