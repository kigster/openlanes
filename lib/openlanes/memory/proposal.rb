# frozen_string_literal: true

require "json"

module OpenLanes
  module Memory
    # One lesson the curator proposes, as it prints it: a line of JSON in its
    # own output, which the harness reads. The curator writes no file, for
    # the reason an agent writes no journal file: one writer, and nothing an
    # agent says reaches the repository unchecked.
    #
    #   {"lesson": {"slug": "real-plan-trees-in-specs", "title": "…",
    #               "applies_to": ["build"], "checked_by": ["staff-reviewer"],
    #               "kind": "practice", "severity": "high",
    #               "finding": "spec stubs File.read; tests the fake", "body": "…"}}
    #
    # The slug is how two plans' proposals are known to be the same lesson:
    # the curator is shown the slugs already waiting and the lessons already
    # active, and reuses one when it sees the same thing again. Promotion
    # counts plans per slug and makes no judgement of its own.
    #
    # @!attribute [r] slug
    #   @return [String] a lesson's id, or a new name in lower-case words
    # @!attribute [r] finding
    #   @return [String] the evidence from this plan, one line
    # @!attribute [r] body
    #   @return [String] why, and what to do instead
    Proposal = Data.define(:slug, :title, :applies_to, :checked_by, :kind, :severity, :finding, :body) do
      # The key of the JSON object a proposal line holds.
      const_set(:KEY, "lesson")

      # A line worth trying to read.
      const_set(:CANDIDATE, /\A`*\{\s*"lesson"\s*:/)

      # A line that looked like a proposal and was not one.
      const_set(:Rejection, Data.define(:line, :reason))

      # The fields a proposal cannot do without.
      const_set(:REQUIRED, %w[slug title finding body].freeze)

      # The longest body kept. A lesson is a paragraph, not a document.
      const_set(:BODY_MAX, 1_500)

      # The longest evidence line kept.
      const_set(:FINDING_MAX, 300)

      class << self
        # @param text [String, nil] what the curator said
        # @return [Array<OpenLanes::Memory::Proposal, OpenLanes::Memory::Proposal::Rejection>]
        def scan(text)
          text.to_s.each_line.filter_map do |raw|
            line = raw.strip
            read(line) if line.match?(self::CANDIDATE)
          end
        end

        # @param line [String]
        # @return [OpenLanes::Memory::Proposal, OpenLanes::Memory::Proposal::Rejection]
        def read(line)
          value = JSON.parse(line.gsub(/\A`+|`+\z/, ""))[self::KEY]
          problem = problem_with(value)
          problem ? self::Rejection.new(line:, reason: problem) : from(value)
        rescue JSON::ParserError => e
          self::Rejection.new(line:, reason: "not JSON: #{e.message.lines.first.to_s.strip}")
        end

        private

        # @param value [Object]
        # @return [String, nil] why it is not a proposal
        def problem_with(value)
          return "#{self::KEY} is not an object" unless value.is_a?(Hash)

          missing = self::REQUIRED.reject { value[it].is_a?(String) && !value[it].strip.empty? }
          "#{missing.join(", ")} missing" unless missing.empty?
        end

        # @param value [Hash]
        # @return [OpenLanes::Memory::Proposal]
        def from(value)
          new(slug: value["slug"].strip,
            title: value["title"].strip,
**lists(value),
**choices(value),
            finding: value["finding"].split.join(" ")[0, self::FINDING_MAX],
            body: value["body"].strip[0, self::BODY_MAX])
        end

        # @return [Hash{Symbol => Array<String>}]
        def lists(value) = %i[applies_to checked_by].to_h { [it, Array(value[it.to_s]).map(&:to_s)] }

        # @return [Hash{Symbol => String, nil}] left nil for {Lesson}'s defaults
        def choices(value) = %i[kind severity].to_h { [it, value[it.to_s]&.to_s] }
      end
    end
  end
end
