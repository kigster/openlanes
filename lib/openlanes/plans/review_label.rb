# frozen_string_literal: true

module OpenLanes
  module Plans
    # A label that says where a pull request stands in review (decision M3).
    #
    # A pull request carries at most one of these at a time; a new verdict
    # replaces the previous one. This file is the only place under `lib/` that
    # spells a label's name, so the CLI help, the docs table and the `gh`
    # calls cannot drift apart.
    ReviewLabel = Data.define(:name, :colour, :meaning, :passing) do
      alias_method :passing?, :passing

      # @return [String] the name, so a label interpolates as itself
      def to_s = name
    end

    class ReviewLabel
      ALL = [
        new(name: "ready-for-review", colour: "c2e0c6", meaning: "PR open, review not started", passing: false),
        new(name: "review-in-progress", colour: "fff3b0", meaning: "hansolo is reviewing", passing: false),
        new(name: "review-passed",
          colour: "1d76db",
          meaning: "passed with non-critical findings still open",
          passing: true),
        new(name: "ready-to-merge", colour: "2ea043", meaning: "passed with nothing open", passing: true),
        new(name: "review-rejected", colour: "b60205", meaning: "changes needed", passing: false),
        new(name: "ok-to-merge", colour: "1a7f37", meaning: "chewie verified it", passing: true)
      ].freeze

      # The label the publisher puts on a pull request it has just opened.
      INITIAL = ALL.first

      # The verdict accepted even while CI is red.
      REJECTED = ALL.find { |l| l.name == "review-rejected" }

      class << self
        # @return [Array<String>] every label name, in M3 order
        def names = ALL.map(&:name)

        # @return [Array<ReviewLabel>] the verdicts refused while CI is red
        def passing = ALL.select(&:passing?)

        # @param name [String, ReviewLabel]
        # @return [ReviewLabel]
        # @raise [OpenLanes::Error] naming the valid labels
        def fetch(name)
          ALL.find { |l| l.name == name.to_s } ||
            raise(Error, "unknown review label #{name.to_s.inspect}; one of: #{names.join(", ")}")
        end
      end
    end
  end
end
