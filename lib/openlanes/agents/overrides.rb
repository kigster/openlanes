# frozen_string_literal: true

module OpenLanes
  module Agents
    # `.openlanes/config.yml` `agents:`: what one machine changes about an
    # agent without editing its `agents/*.md`.
    #
    #   agents:
    #     backend-coder: { rounds: 3, timeout: 3600, extension_cap: 1200 }
    #
    # The definition file stays the source of every default. An entry here
    # replaces the frontmatter's value for the keys it names and nothing
    # else, so an agent the file leaves out runs exactly as its definition
    # says, and this class holds no default of its own.
    #
    # {Registry} lays it over each definition as it loads, which is why
    # every reader of an {Agent} (the round count, the clock, {Profile},
    # {Roster}) sees the value in force without asking a second place.
    #
    # @!attribute [r] table
    #   @return [Hash{String => Hash{Symbol => Object}}] agent name → the
    #     {Agent} attributes it overrides
    Overrides = Data.define(:table) do
      def initialize(table: {}) = super

      # @param name [String, Symbol]
      # @return [Hash{Symbol => Object}] empty for an agent the file leaves alone
      def for(name) = table.fetch(name.to_s, {})

      # @param agent [OpenLanes::Agents::Agent] as its definition wrote it
      # @return [OpenLanes::Agents::Agent] with this machine's values laid over
      def apply(agent) = self.for(agent.name).empty? ? agent : agent.with(**self.for(agent.name))

      # @return [Hash{String => Hash{String => Object}}] `agents:` as the file holds it
      def to_settings = table.transform_values { it.transform_keys(&:to_s) }
    end

    class Overrides
      # What an entry may set, read from the schema so the two cannot disagree.
      KEYS = Config::Schema.static.dig("properties", "agents", "additionalProperties", "properties").keys.freeze

      # The keys that count seconds.
      SECONDS = %w[timeout extension_cap extension_ceiling].freeze

      class << self
        # @param value [Object, nil] the `agents:` section as YAML gave it
        # @param path [String] for every error message
        # @return [OpenLanes::Agents::Overrides]
        # @raise [OpenLanes::Error] on an unknown agent or key, or a value
        #   its key cannot take
        def parse(value, path:)
          return new if value.nil?
          raise Error, "#{path}: agents: must be a mapping of agent name to its settings" unless value.is_a?(Hash)

          new(table: value.to_h { |name, entry| [agent!(name.to_s, path), entry(entry, name, path)] }
                          .reject { |_, entry| entry.empty? }.freeze)
        end

        private

        # @return [String] the name, when an `agents/*.md` answers to it
        def agent!(name, path)
          return name if Names.all.include?(name)

          raise Error, "#{path}: agents: unknown agent #{name}; known: #{Names.all.join(", ")}"
        end

        # @return [Hash{Symbol => Object}] one agent's settings, each checked
        def entry(entry, name, path)
          raise Error, "#{path}: agents.#{name}: must be a mapping of setting to value" unless entry.is_a?(Hash)

          settings = entry.transform_keys(&:to_s).compact
          unknown = settings.keys - KEYS
          raise Error, "#{path}: agents.#{name}: unknown key #{unknown.join(", ")}; known: #{KEYS.join(", ")}" unless unknown.empty?

          settings.to_h do |key, setting|
            [key.to_sym, checked(key, setting) { |why| refuse("#{path}: agents.#{name}.#{key}", setting, why) }]
          end
        end

        # @yieldparam why [String] what the value is not, when it is refused
        # @return [Object] the value as the {Agent} holds it
        def checked(key, value)
          case key
          when *SECONDS then whole?(value) ? value : yield("a whole number of seconds above zero")
          when "rounds" then whole?(value) && value <= Agent::MAX_ROUNDS ? value : yield("a whole number from 1 to #{Agent::MAX_ROUNDS}")
          when "effort" then Adapters.effort?(value) ? value.to_s : yield("one of #{Adapters::EFFORTS.join(", ")}")
          else value.is_a?(String) && !value.strip.empty? ? value.strip : yield("a model name")
          end
        end

        # @return [Boolean]
        def whole?(value) = value.is_a?(Integer) && value.positive?

        # @return [void] never returns
        def refuse(where, value, why) = raise(Error, "#{where}: #{value.inspect} is not #{why}")
      end
    end
  end
end
