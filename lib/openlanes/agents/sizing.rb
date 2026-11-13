# frozen_string_literal: true

module OpenLanes
  module Agents
    # `.openlanes.yml` `sizing:`: the model and effort a builder runs on for a
    # plan whose largest unit is small, medium or large ({Plans::UnitSizes}).
    #
    #   sizing:
    #     large: { model: fable, effort: high }
    #
    # A size the file leaves out keeps its default, and so does a key a size
    # leaves out. Fable is above the Claude adapter's ceiling, so it runs only
    # when this table names it ({#uncapped?}): a run that spends Fable money
    # should be one somebody wrote down.
    #
    # @!attribute [r] table
    #   @return [Hash{String => Hash{Symbol => String}}] size → `{model:, effort:}`
    Sizing = Data.define(:table) do
      def initialize(table: Sizing::DEFAULTS) = super

      # @param size [String, nil] one of {Plans::UnitSizes::SIZES}
      # @return [Hash{Symbol => String}, nil] `{model:, effort:}`; nil for no size
      def for(size) = size && table[size.to_s]

      # @param size [String, nil]
      # @return [Boolean] whether the model this size names may pass the
      #   adapter's ceiling: true only for a model the operator configured
      def uncapped?(size) = !size.nil? && table[size.to_s] != Sizing::DEFAULTS[size.to_s]
    end

    class Sizing
      # small → sonnet/medium, medium → opus/medium, large → opus/high.
      DEFAULTS = {
        "small"  => { model: "sonnet", effort: "medium" }.freeze,
        "medium" => { model: "opus", effort: "medium" }.freeze,
        "large"  => { model: "opus", effort: "high" }.freeze
      }.freeze

      # What each size may set.
      KEYS = %w[model effort].freeze

      # The phases that build, the only ones sizing applies to.
      PHASES = %w[build frontend].freeze

      class << self
        # @param value [Object, nil] the `sizing:` section as YAML gave it
        # @param path [String] for every error message
        # @return [OpenLanes::Agents::Sizing]
        # @raise [OpenLanes::Error] on an unknown size or key, or an effort
        #   no adapter knows
        def parse(value, path:)
          return new if value.nil?
          raise Error, "#{path}: sizing: must be a mapping, e.g. `sizing: { large: { model: fable } }`" unless value.is_a?(Hash)

          table = DEFAULTS.dup
          value.each do |size, entry|
            table[size.to_s] = DEFAULTS.fetch(size.to_s) { raise Error, unknown_size(path, size) }.merge(entry(entry, size, path))
          end
          new(table: table.freeze)
        end

        private

        # @return [String]
        def unknown_size(path, size) = "#{path}: sizing: unknown size #{size}; known: #{Plans::UnitSizes::SIZES.join(", ")}"

        # @return [Hash{Symbol => String}]
        def entry(entry, size, path)
          raise Error, "#{path}: sizing.#{size}: must be a mapping of model and effort" unless entry.is_a?(Hash)

          settings = entry.transform_keys(&:to_s)
          unknown = settings.keys - KEYS
          raise Error, "#{path}: sizing.#{size}: unknown key #{unknown.join(", ")}; known: #{KEYS.join(", ")}" unless unknown.empty?

          effort!(settings["effort"]&.to_s, size, path)
          settings.compact.to_h { |key, value| [key.to_sym, value.to_s] }
        end

        # @return [void]
        def effort!(effort, size, path)
          return if effort.nil? || Adapters::EFFORTS.include?(effort)

          raise Error, "#{path}: sizing.#{size}.effort: #{effort} is not one of #{Adapters::EFFORTS.join(", ")}"
        end
      end
    end
  end
end
