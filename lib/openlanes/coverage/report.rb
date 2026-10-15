# frozen_string_literal: true

require "json"

module OpenLanes
  module Coverage
    # One coverage report, reduced to the two counts the gate compares.
    #
    # Every way a report can fail to say anything (missing, unreadable,
    # malformed, or present with nothing instrumented) is the same answer: 0%,
    # with the reason kept in {#problem}. A gate that passed on "could not
    # tell" would pass a project whose test command stopped writing its
    # report, which is the easiest way to stop being measured.
    #
    # @!attribute [r] covered
    #   @return [Numeric] lines hit at least once
    # @!attribute [r] relevant
    #   @return [Numeric] instrumented lines
    # @!attribute [r] problem
    #   @return [String, nil] why the report counts as 0%, nil when it was read
    Report = Data.define(:covered, :relevant, :problem) do
      def initialize(covered: 0, relevant: 0, problem: nil) = super

      # Computed from the counts, never from a figure a tool rounded: simplecov
      # truncates to two decimals and istanbul floors, so 94.995 would read as
      # a pass at 95.
      #
      # @return [Float] 0.0 to 100.0
      def percent
        return 0.0 if problem || !relevant.positive?

        (covered * 100r / relevant).to_f
      end

      # @return [Boolean] whether the report said anything at all
      def read? = problem.nil?
    end

    class Report
      # The parser for each format. Each answers `parse(text)` with
      # `[covered, relevant]`, or raises {Malformed}.
      PARSERS = { lcov: "Lcov", cobertura: "Cobertura", istanbul: "Istanbul", simplecov: "Simplecov" }.freeze

      class << self
        # @param format [Symbol] one of {Config::FORMATS}
        # @param path [String]
        # @return [OpenLanes::Coverage::Report]
        def read(format:, path:)
          parser = Coverage.const_get(PARSERS.fetch(format.to_sym))
          return new(problem: "#{path} is missing") unless File.exist?(path)

          covered, relevant = parser.parse(File.read(path))
          return new(covered:, relevant:, problem: "#{path} has no instrumented lines") unless relevant.positive?

          new(covered:, relevant:)
        rescue SystemCallError, IOError => e
          new(problem: "#{path} cannot be read (#{e.message})")
        rescue Malformed, JSON::ParserError => e
          new(problem: "#{path} is not a #{format} report (#{e.message.lines.first.to_s.strip})")
        end
      end
    end
  end
end
