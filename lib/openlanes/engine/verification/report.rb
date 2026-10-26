# frozen_string_literal: true

module OpenLanes
  module Engine
    module Verification
      # verifier's `verification/<round>/report.md`, read back for the comment
      # the engine posts (M1, M14). verifier cannot post it: the comment links
      # the screenshot by the SHA of a commit only the engine makes.
      #
      # The shape verifier.md asks for:
      #
      #   # Verification, round 1
      #
      #   Verdict: rejected
      #
      #   ## Steps
      #
      #   1. Open the board: passed
      #   2. Click New game: failed (step-02.png)
      #
      #   ## Failing step
      #
      #   - Step: 2
      #   - What: Click "New game"
      #   - Expected: a 9 by 9 grid appears
      #   - Seen: the page says "500 Internal Server Error"
      #
      # A report that leaves a field out reads as nil there, and the comment
      # says what it does have. A missing verdict is nil too: the signature,
      # not the report, is what the dispatcher acts on.
      #
      # @!attribute [r] verdict
      #   @return [Symbol, nil] :verified, :rejected or :skipped
      # @!attribute [r] step
      #   @return [Integer, nil] the failing step's number
      # @!attribute [r] what
      #   @return [String, nil] the failing step, as How to test words it
      # @!attribute [r] expected
      #   @return [String, nil]
      # @!attribute [r] seen
      #   @return [String, nil]
      Report = Data.define(:verdict, :step, :what, :expected, :seen) do
        def initialize(verdict: nil, step: nil, what: nil, expected: nil, seen: nil) = super

        # @return [String, nil] the failing step's screenshot, `step-02.png`
        def screenshot = step && format(Report::STEP_PNG, step)
      end

      class Report
        # How a step's screenshot is named (M14).
        STEP_PNG = "step-%02d.png"

        # The section holding the failure.
        FAILING = "## Failing step"

        # One `Key: value` line, bulleted or not.
        FIELD = /\A\s*(?:[-*]\s+)?\**(?<key>Step|What|Expected|Seen)\**\s*:\s*\**\s*(?<value>.+?)\s*\z/i

        class << self
          # @param path [String]
          # @return [Report]
          def read(path) = parse(File.read(path, encoding: "UTF-8"))

          # @param text [String]
          # @return [Report]
          def parse(text)
            lines = text.to_s.lines.map(&:chomp)
            fields = failing(lines).filter_map { FIELD.match(it) }.to_h { [it[:key].downcase.to_sym, it[:value]] }
            new(verdict: verdict(lines),
              step: fields[:step]&.[](/\d+/)&.to_i,
              what: fields[:what],
              expected: fields[:expected],
              seen: fields[:seen])
          end

          private

          # @return [Symbol, nil]
          def verdict(lines)
            word = lines.filter_map { it[/\A\s*\**Verdict\**\s*:\s*\**\s*(\w+)/i, 1] }.first.to_s.downcase
            return :skipped if word.start_with?("skip")
            return :verified if word.start_with?("verif", "pass")

            :rejected if word.start_with?("reject", "fail")
          end

          # @return [Array<String>] the lines under {FAILING}, up to the next heading
          def failing(lines)
            start = lines.index { it.strip.casecmp?(FAILING) } or return []
            lines[(start + 1)..].take_while { !it.start_with?("#") }
          end
        end
      end
    end
  end
end
