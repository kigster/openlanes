# frozen_string_literal: true

module OpenLanes
  module Setup
    # `architecture_decisions:` in `.openlanes.yml`: what the repository holds
    # now, what the person wants, and how the code gets from one to the other.
    #
    # @!attribute [r] detail
    #   @return [Symbol, nil] how much the person chose to say; nil when nobody was asked
    # @!attribute [r] current
    #   @return [OpenLanes::Setup::Architecture]
    # @!attribute [r] target
    #   @return [OpenLanes::Setup::Architecture]
    # @!attribute [r] migration
    #   @return [Symbol, nil] one of {MIGRATIONS}; nil when nothing has to move
    ArchitectureDecisions = Data.define(:detail, :current, :target, :migration) do
      # @return [Boolean] whether nothing is known, so the key is left out of the file
      def empty? = current.blank? && target.blank? && detail.nil? && migration.nil?

      # @return [Hash{String => Object}, nil] the file's shape; nil when {#empty?}
      def to_file
        return nil if empty?

        { "version" => self.class::VERSION, "detail" => detail&.to_s, "current" => current.to_file,
          "target" => target.to_file, "migration" => migration&.to_s }.compact
      end

      # The wanted architecture in the shape `docs/decisions/stack.md` and the
      # CI scaffold read. Node beside one other language is that language's asset
      # tooling, so the other is named; between two others nothing is guessed.
      #
      # @return [OpenLanes::Setup::Stack]
      def stack
        Stack.new(language: main_language&.to_s,
          frameworks: names(:frameworks),
          front_end: names(:front_end).first,
          persistence: names(:persistence).first,
          caching: names(:caching).first,
          logins: names(:logins).first,
          deployment: names(:deployment).first,
          from: (origin if migration == :port),
          to: (destination if migration == :port))
      end

      private

      # @return [Symbol, nil]
      def main_language
        languages = target.languages - %i[other]
        others = languages - %i[node]
        others.empty? ? languages.first : (others.first if others.one?)
      end

      # @return [Array<String>] what was answered, without the two non-answers
      def names(attribute, source = target) = (source.public_send(attribute) - %i[other none]).map(&:to_s)

      # @return [String]
      def origin = [*current.languages, *names(:frameworks, current)].join("/")

      # @return [String]
      def destination = [*target.languages, *names(:frameworks)].join("/")
    end

    # Reading the file's shape back, kept beside the value it builds.
    class ArchitectureDecisions
      # The serialized shape's version, so a later change can read an older file.
      VERSION = 1

      # How the existing code reaches what is wanted.
      MIGRATIONS = %i[port fresh].freeze

      # Every key the section may hold.
      KEYS = %w[version detail current target migration].freeze

      class << self
        # @return [OpenLanes::Setup::ArchitectureDecisions] nothing decided yet
        def none = new(detail: nil, current: Architecture.new, target: Architecture.new, migration: nil)

        # @param value [Hash, nil] the section as YAML gave it
        # @param path [String] named in the error
        # @return [OpenLanes::Setup::ArchitectureDecisions, nil]
        # @raise [OpenLanes::Error] when the section does not fit the closed lists
        def parse(value, path:)
          return nil if value.nil?

          settings = mapping(value, path)
          new(detail: member(settings, "detail", Architecture::DETAILS, path),
            migration: member(settings, "migration", MIGRATIONS, path),
            current: Architecture.new(settings.fetch("current", {})),
            target: Architecture.new(settings.fetch("target", {})))
        rescue Dry::Struct::Error => e
          raise Error, "#{path}: architecture_decisions: #{e.message}"
        end

        # What an older file's `ci:` and `stack:` said, as far as the closed
        # lists can hold it, so `--reconfigure` starts from those answers.
        #
        # @param legacy_ci [Hash, nil]
        # @param stack [Hash, nil]
        # @return [OpenLanes::Setup::ArchitectureDecisions]
        def from_legacy(legacy_ci:, stack:)
          fields = (stack || {}).slice(:front_end, :persistence, :caching, :logins, :deployment, :frameworks)
                   .merge(languages: stack&.dig(:language), ci: legacy_ci&.dig(:provider))
          held = Architecture.new(fields.to_h { |name, value| [name, known(name, value)] })
          new(detail: nil, current: held, target: held, migration: nil)
        end

        private

        # @return [Hash{String => Object}]
        def mapping(value, path)
          raise Error, "#{path}: architecture_decisions: must be a mapping" unless value.is_a?(Hash)

          settings = value.transform_keys(&:to_s)
          unknown = settings.keys - KEYS
          raise Error, "#{path}: architecture_decisions: unknown key #{unknown.join(", ")}" unless unknown.empty?

          settings
        end

        # @return [Symbol, nil]
        def member(settings, key, values, path)
          word = settings[key]&.to_s&.to_sym
          return word if word.nil? || values.include?(word)

          raise Error, "#{path}: architecture_decisions.#{key}: #{word} is not one of #{values.join(", ")}"
        end

        # @return [Array<Symbol>] the words a closed list has, the rest dropped
        def known(name, value)
          Array(value).map { it.to_s.strip.downcase.to_sym } & Architecture.values(name)
        end
      end
    end
  end
end
