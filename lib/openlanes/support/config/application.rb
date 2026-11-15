# frozen_string_literal: true

module OpenLanes
  class Config
    # The `application:` section of `.openlanes/config.yml`: the application
    # openlanes is working on, as distinct from `project:` (a heading) and
    # `app:` (the processes the Preview tab keeps running).
    #
    #   application:
    #     name: Demo App
    #     description: Books appointments for small clinics
    #     current_phase: beta          # mvp | alpha | beta | in-production
    #     commands:
    #       setup: bin/setup
    #       start: [bin/rails server, bin/vite dev]
    #       backend_tests: bundle exec rspec
    #
    # Every key is optional. `openlanes init` writes them all, empty, so a
    # person sees what there is to fill in; an empty one reads as unset.
    #
    # @!attribute [r] name
    #   @return [String, nil]
    # @!attribute [r] description
    #   @return [String, nil]
    # @!attribute [r] current_phase
    #   @return [Symbol, nil] one of {PHASES}
    # @!attribute [r] commands
    #   @return [Hash{Symbol => String, Array<String>}] only the commands that
    #     were given; the {LISTS} as arrays, the rest as one string each
    Application = Data.define(:name, :description, :current_phase, :commands) do
      def initialize(name: nil, description: nil, current_phase: nil, commands: {}) = super

      # @return [Boolean] whether nothing at all was said
      def empty? = name.nil? && description.nil? && current_phase.nil? && commands.empty?

      # @param key [Symbol, String] one of {COMMANDS}
      # @return [String, Array<String>, nil] nil when the file gives none
      def command(key) = commands[key.to_sym]

      # @return [Hash{String => Object}] the section as the file would hold it
      def to_h
        { "name" => name, "description" => description, "current_phase" => current_phase&.to_s,
          "commands" => (commands.transform_keys(&:to_s) unless commands.empty?) }.compact
      end
    end

    class Application
      # Every key the section may hold.
      KEYS = Schema.keys_for("application").freeze

      # What `current_phase` may say.
      PHASES = Schema.enum_for("application", "current_phase").map(&:to_sym).freeze

      # Every command the section may name, in the order they run.
      COMMANDS = Schema.static.dig("properties", "application", "properties", "commands", "properties").keys.freeze

      # The commands that are lists: several things may start, or stop, together.
      LISTS = %w[start stop].freeze

      class << self
        # @param value [Hash, nil] the section as YAML read it
        # @param path [String] for every error message
        # @return [OpenLanes::Config::Application, nil] nil when the section
        #   is absent or says nothing
        # @raise [OpenLanes::Error] for a key or a value it does not know
        def parse(value, path:)
          return nil if value.nil?
          raise Error, "#{path}: application: must be a mapping of #{KEYS.join(", ")}" unless value.is_a?(Hash)

          data = value.transform_keys(&:to_s)
          known!(data.keys, KEYS, "application", path)
          application = new(name: text(data["name"], "application.name", path),
            description: text(data["description"], "application.description", path),
            current_phase: phase(data["current_phase"], path),
            commands: commands(data["commands"], path))
          application.empty? ? nil : application
        end

        private

        # @return [void]
        def known!(keys, known, where, path)
          unknown = keys - known
          return if unknown.empty?

          raise Error, "#{path}: #{where}: unknown key#{"s" unless unknown.size == 1} #{unknown.join(", ")}; known: #{known.join(", ")}"
        end

        # @return [String, nil] nil for an empty value, which is an unset one
        def text(value, where, path)
          return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
          return value.strip if value.is_a?(String)

          raise Error, "#{path}: #{where}: must be text, not #{value.inspect}"
        end

        # @return [Symbol, nil]
        def phase(value, path)
          return nil if value.nil? || value.to_s.strip.empty?

          word = value.to_s.strip.downcase.tr("_", "-").to_sym
          return word if PHASES.include?(word)

          raise Error, "#{path}: application.current_phase: #{value.inspect} is not one of #{PHASES.join(", ")}"
        end

        # @return [Hash{Symbol => String, Array<String>}] only what was given
        def commands(value, path)
          return {} if value.nil?
          raise Error, "#{path}: application.commands: must be a mapping of #{COMMANDS.join(", ")}" unless value.is_a?(Hash)

          data = value.transform_keys(&:to_s)
          known!(data.keys, COMMANDS, "application.commands", path)
          COMMANDS.filter_map do |key|
            where = "application.commands.#{key}"
            given = LISTS.include?(key) ? list(data[key], where, path) : text(data[key], where, path)
            [key.to_sym, given] unless given.nil? || given.empty?
          end.to_h
        end

        # One command is as good as a list of one, so a person who starts a
        # single thing need not write brackets.
        #
        # @return [Array<String>]
        def list(value, where, path)
          entries = value.is_a?(Array) ? value : [value]
          entries.filter_map { text(it, where, path) }
        end
      end
    end
  end
end
