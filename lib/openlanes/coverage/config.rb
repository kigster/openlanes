# frozen_string_literal: true

module OpenLanes
  module Coverage
    # The `coverage:` section of a project's `.openlanes.yml` (M15, amended
    # 2026-10-17). One of two shapes, never both:
    #
    #   coverage:                 # the figure, printed by a command
    #     command: bundle exec rspec
    #     report_command: jq '.total.lines.percent' coverage/coverage.json
    #     minimum: 95
    #
    #   coverage:                 # a report file, read by a parser here
    #     command: npm test -- --coverage
    #     report:  coverage/lcov.info
    #     format:  lcov           # lcov | cobertura | istanbul | simplecov
    #     minimum: 95
    #
    # `command` and `minimum` are required in both. A key the gate ignored
    # would be a promise nobody checks, which is the failure this section
    # exists to end; so, as everywhere in `.openlanes.yml`, anything
    # unexpected is an error naming the file and the section. A
    # `report_command` beside a `format` is refused rather than read as one
    # of them: which of the two the author meant is exactly what is unknown.
    #
    # It lives in the file a project already has rather than in a second one
    # beside it (the first M15 had `.openlanes.coverage.yml`): one project's
    # settings in two files is two places to look, and one gets forgotten.
    #
    # @!attribute [r] path
    #   @return [String] the `.openlanes.yml` it was read from
    # @!attribute [r] command
    #   @return [String] run through `sh -c` in the checkout
    # @!attribute [r] report
    #   @return [String, nil] relative to the checkout, as written; nil with
    #     a {#report_command}
    # @!attribute [r] format
    #   @return [Symbol, nil] one of {FORMATS}; nil with a {#report_command}
    # @!attribute [r] report_command
    #   @return [String, nil] run through `sh -c` in the checkout after
    #     {#command}; its STDOUT is the line percentage
    # @!attribute [r] minimum
    #   @return [Float] the lowest line percentage that passes, 0 to 100
    Config = Data.define(:path, :command, :report, :format, :report_command, :minimum) do
      def initialize(report: nil, format: nil, report_command: nil, **rest) = super

      # @param root [String] the checkout the report path is relative to
      # @return [String, nil] absolute; nil with a {#report_command}
      def report_path(root) = report && File.expand_path(report, root)

      # @return [Boolean] whether the figure comes from {#report_command}
      def report_command? = !report_command.nil?

      # Where the figure comes from, as a verdict names it.
      #
      # @return [String]
      def source = report_command? ? "report_command: `#{report_command}`" : "#{format}: #{report}"

      # The section as `.openlanes.yml` holds it.
      #
      # @return [Hash{String => Object}]
      def to_h
        { "command" => command, "report" => report, "format" => format&.to_s,
          "report_command" => report_command, "minimum" => minimum }.compact
      end
    end

    class Config
      # The section's key at the top of `.openlanes.yml`.
      SECTION = "coverage"

      # Report formats with a parser. Each reports lines (plan decision 1).
      FORMATS = %i[lcov cobertura istanbul simplecov].freeze

      # Every key the section may hold.
      KEYS = %w[command report format report_command minimum].freeze

      # Keys both shapes require.
      REQUIRED = %w[command minimum].freeze

      # The two shapes, as every error and the setup note spell them.
      SHAPES = "report_command alone, or report with format"

      class << self
        # @param root [String] a checkout
        # @return [OpenLanes::Coverage::Config, nil] nil when its
        #   `.openlanes.yml` has no `coverage:` section, or there is no file
        # @raise [OpenLanes::Coverage::Invalid] when the section, or the file
        #   around it, cannot be used
        def load(root)
          OpenLanes::Config.load(root).coverage
        rescue Invalid
          raise
        rescue OpenLanes::Error => e
          raise Invalid, e.message
        end

        # @param value [Object] what YAML gave for `coverage:`
        # @param path [String] the `.openlanes.yml`, named in every error
        # @return [OpenLanes::Coverage::Config]
        # @raise [OpenLanes::Coverage::Invalid]
        def parse(value, path:)
          fail_with(path, ": must be a mapping with command, minimum, and #{SHAPES}") unless value.is_a?(Hash)

          settings = value.transform_keys(&:to_s)
          unknown = settings.keys - KEYS
          fail_with(path, ": unknown key #{unknown.join(", ")}; known: #{KEYS.join(", ")}") unless unknown.empty?
          missing = REQUIRED - settings.keys
          fail_with(path, ": missing key #{missing.join(", ")}") unless missing.empty?
          shape!(settings, path)

          new(path:,
            command: text_of(settings, "command", path),
            minimum: minimum_of(settings["minimum"], path),
            **source_of(settings, path))
        end

        private

        # @param message [String] after the section's name: ": …" for the
        #   section, ".key: …" for one key, as the rest of `.openlanes.yml` reads
        # @return [void] never returns
        def fail_with(path, message) = raise(Invalid, "#{path}: #{SECTION}#{message}")

        # Exactly one shape, said whole.
        #
        # @return [void]
        def shape!(settings, path)
          given = %w[report format report_command].select { settings.key?(it) }
          return if [%w[report_command], %w[report format]].include?(given)

          problem =
            if given.empty? then "says nowhere to read the figure"
            elsif given.include?("report_command") then "report_command replaces #{(given - %w[report_command]).join(" and ")}"
            else "#{given.first} without #{(%w[report format] - given).first}"
            end
          fail_with(path, ": #{problem}; give #{SHAPES}")
        end

        # @return [Hash{Symbol => Object}]
        def source_of(settings, path)
          return { report_command: text_of(settings, "report_command", path) } if settings.key?("report_command")

          { report: text_of(settings, "report", path), format: format_of(settings["format"], path) }
        end

        # @return [String]
        def text_of(settings, key, path)
          value = settings[key]
          return value.strip if value.is_a?(String) && !value.strip.empty?

          fail_with(path, ".#{key}: must be a non-empty string, not #{value.inspect}")
        end

        # @return [Symbol]
        def format_of(value, path)
          format = value.to_s.strip.downcase.to_sym
          return format if FORMATS.include?(format)

          fail_with(path, ".format: #{value.inspect} is not one of #{FORMATS.join(", ")}")
        end

        # A quoted `"95"` is refused rather than converted: YAML that types a
        # number as a string was written by hand, and the hand may have meant
        # something else.
        #
        # @return [Float]
        def minimum_of(value, path)
          return value.to_f if value.is_a?(Numeric) && value.between?(0, 100)

          fail_with(path, ".minimum: #{value.inspect} is not a number from 0 to 100")
        end
      end
    end
  end
end
