# frozen_string_literal: true

module OpenLanes
  module Plans
    # Telling "this belongs to no specification" apart from "nobody could tell".
    #
    # Both end up without a plan number, and filing them under one marker loses
    # the difference between a finished thought and an open question. A
    # dependency bump genuinely implements no specification and never will —
    # that is an assertion, and `[dev]` records it. A pull request that adds
    # Schedule K-1 for four tax years plainly implements *something*; nothing
    # here could work out what, and `[none]` records that instead, as a job left
    # for a human rather than a verdict.
    #
    # The bar for `[dev]` is deliberately high. Marking real work as `[dev]`
    # tells everyone afterwards it was never worth a plan, and nobody re-opens a
    # question that looks settled. `[none]` is visibly unfinished, so the cost of
    # guessing wrong in that direction is somebody spending a minute on it.
    module DevWork
      module_function

      # Titles that say what they are: dependency bumps, release chores, CI.
      TITLES = [
        /\Abump\s+\S+\s+from\s+\S+\s+to\s+\S+/i,
        /\A(?:chore|ci|build|deps|style|refactor)(?:\([^)]*\))?:/i,
        /\Abump\s+(?:to\s+)?v?\d+\.\d+/i
      ].freeze

      # Paths that are how the project is built rather than what it does.
      PLUMBING = %r{\A(?:\.github/|\.circleci/|\.devcontainer/|bin/|scripts/|
                         Dockerfile|\.dockerignore|Gemfile(?:\.lock)?|justfile|Rakefile|
                         \.rubocop\.ya?ml|\.standard\.ya?ml|\.gitignore|\.tool-versions)}x

      # Files that say nothing either way, so they neither prove plumbing nor
      # disprove it — every pull request in this tool's world touches `.plans`.
      NEUTRAL = %r{\A(?:#{PLANS_DIR}/|CHANGELOG|README)}

      # @param title [String]
      # @param files [Array<String>] paths in the diff
      # @return [Boolean] whether this can be *asserted* to implement no plan
      def developer?(title, files = [])
        return true if TITLES.any? { |pattern| title.to_s.match?(pattern) }

        judged = Array(files).reject { |path| path.match?(NEUTRAL) }
        return false if judged.empty?

        judged.all? { |path| path.match?(PLUMBING) }
      end

      # @param title [String]
      # @param files [Array<String>]
      # @return [String] the marker to stamp on it
      def marker(title, files = []) = developer?(title, files) ? NO_PLAN_PREFIX : NONE_PREFIX
    end
  end
end
