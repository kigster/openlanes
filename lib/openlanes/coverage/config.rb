# frozen_string_literal: true

require "yaml"

module OpenLanes
  module Coverage
    # A project's `.openlanes.coverage.yml`, at the root of the checkout:
    #
    #   command: npm test -- --coverage
    #   report:  coverage/lcov.info
    #   format:  lcov            # lcov | cobertura | istanbul | simplecov
    #   minimum: 95
    #
    # All four keys are required and nothing else is allowed. A key the gate
    # ignored would be a promise nobody checks, which is the failure this file
    # exists to end; so, as with `.openlanes.yml`, anything unexpected is an
    # error naming the file.
    #
    # @!attribute [r] path
    #   @return [String] the file it was read from
    # @!attribute [r] command
    #   @return [String] run through `sh -c` in the checkout
    # @!attribute [r] report
    #   @return [String] relative to the checkout, as written
    # @!attribute [r] format
    #   @return [Symbol] one of {FORMATS}
    # @!attribute [r] minimum
    #   @return [Float] the lowest line percentage that passes, 0 to 100
    Config = Data.define(:path, :command, :report, :format, :minimum) do
      # @param root [String] the checkout the report path is relative to
      # @return [String] absolute
      def report_path(root) = File.expand_path(report, root)
    end

    class Config
      # The file's name, at the checkout's root.
      FILE = ".openlanes.coverage.yml"

      # Report formats with a parser. Each reports lines (plan decision 1).
      FORMATS = %i[lcov cobertura istanbul simplecov].freeze

      # Every key, each required.
      KEYS = %w[command report format minimum].freeze

      class << self
        # @param root [String]
        # @return [OpenLanes::Coverage::Config, nil] nil when there is no file
        # @raise [OpenLanes::Coverage::Invalid]
        def load(root)
          path = File.join(root, FILE)
          return nil unless File.file?(path)

          parse(File.read(path), path:)
        end

        # @param text [String] YAML
        # @param path [String] named in every error
        # @return [OpenLanes::Coverage::Config]
        # @raise [OpenLanes::Coverage::Invalid]
        def parse(text, path:)
          data = YAML.safe_load(text)
          fail_with(path, "expected a mapping with #{KEYS.join(", ")}") unless data.is_a?(Hash)

          settings = data.transform_keys(&:to_s)
          unknown = settings.keys - KEYS
          fail_with(path, "unknown key #{unknown.join(", ")}; known: #{KEYS.join(", ")}") unless unknown.empty?
          missing = KEYS - settings.keys
          fail_with(path, "missing key #{missing.join(", ")}") unless missing.empty?

          new(path:,
            command: text_of(settings, "command", path),
            report:  text_of(settings, "report", path),
            format:  format_of(settings["format"], path),
            minimum: minimum_of(settings["minimum"], path))
        rescue Psych::Exception => e
          fail_with(path, "is not valid YAML (#{e.message.lines.first.to_s.strip})")
        end

        private

        # @return [void] never returns
        def fail_with(path, message) = raise(Invalid, "#{path}: #{message}")

        # @return [String]
        def text_of(settings, key, path)
          value = settings[key]
          return value.strip if value.is_a?(String) && !value.strip.empty?

          fail_with(path, "#{key}: must be a non-empty string, not #{value.inspect}")
        end

        # @return [Symbol]
        def format_of(value, path)
          format = value.to_s.strip.downcase.to_sym
          return format if FORMATS.include?(format)

          fail_with(path, "format: #{value.inspect} is not one of #{FORMATS.join(", ")}")
        end

        # A quoted `"95"` is refused rather than converted: YAML that types a
        # number as a string was written by hand, and the hand may have meant
        # something else.
        #
        # @return [Float]
        def minimum_of(value, path)
          return value.to_f if value.is_a?(Numeric) && value.between?(0, 100)

          fail_with(path, "minimum: #{value.inspect} is not a number from 0 to 100")
        end
      end
    end
  end
end
