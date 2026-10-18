# frozen_string_literal: true

module OpenLanes
  module Plans
    # A label that says where a pull request stands in review (decision R3,
    # which replaced M3's set).
    #
    # A pull request carries at most one of these at a time; a new verdict
    # replaces the previous one. The one exception is {VULNERABILITY}, which
    # sits beside {REJECTED}. This file is the only place under `lib/` that
    # spells a label's name, so the CLI help, the docs table, the `gh` calls
    # and the label sync cannot drift apart.
    ReviewLabel = Data.define(:name, :colour, :meaning, :passing) do
      alias_method :passing?, :passing

      # @return [String] the name, so a label interpolates as itself
      def to_s = name
    end

    class ReviewLabel
      ALL = [
        new(name: "ready-for-review",
          colour: "c2e0c6",
          meaning: "luke and rey are done; the PR waits for a free review slot",
          passing: false),
        new(name: "review-in-progress", colour: "FFBE20", meaning: "the reviewers have started", passing: false),
        new(name: "review-rejected", colour: "F90000", meaning: "at least one ⛔️ or 💣", passing: false),
        new(name: "review-vulnerability",
          colour: "FF0050",
          meaning: "at least one 💣; sits beside review-rejected",
          passing: false),
        new(name: "review-ok-not-perfect", colour: "E8E890", meaning: "no ⛔️ or 💣, but more 🤔 than review.max_hmm (5 by default)", passing: true),
        new(name: "review-approved", colour: "109a10", meaning: "no ⛔️ or 💣, few 🤔", passing: true),
        new(name: "ready-to-merge",
          colour: "5319e7",
          meaning: "chewie-verifier verified it and its E2E tests pass",
          passing: true)
      ].freeze

      # @param name [String]
      # @return [ReviewLabel]
      def self.named(name) = ALL.find { |l| l.name == name }

      # The label the publisher puts on a pull request it has just opened.
      INITIAL = named("ready-for-review")

      # The verdict accepted even while CI is red.
      REJECTED = named("review-rejected")

      # The one label that sits beside another: always next to {REJECTED},
      # since a 💣 is also a rejection. Accepted while CI is red for the same
      # reason {REJECTED} is.
      VULNERABILITY = named("review-vulnerability")

      # The verdict for a review with no ⛔️ or 💣 but too many 🤔.
      OK_NOT_PERFECT = named("review-ok-not-perfect")

      # The verdict for everything else.
      APPROVED = named("review-approved")

      # chewie-verifier's label, and the one the coverage gate withholds.
      READY_TO_MERGE = named("ready-to-merge")

      # Not a verdict, and so not in {ALL}: {Vcs::LabelSync} never creates or
      # recolours it. Its presence on a repository is the one sign that
      # {Vcs::LabelMigration} has finished there. The colour of
      # `ready-to-merge` could not be that sign: an earlier release recoloured
      # it without moving a single pull request.
      MIGRATED = new(name: "openlanes-r3-labels",
        colour: "ededed",
        meaning: "openlanes moved this repository's open PRs from M3's review labels to R3's",
        passing: false)

      # M3's names for verdicts R3 kept under another name: `review-passed`
      # is R3's {OK_NOT_PERFECT}, and chewie's `ok-to-merge` is R3's
      # {READY_TO_MERGE}.
      RENAMED = { "review-passed" => OK_NOT_PERFECT, "ok-to-merge" => READY_TO_MERGE }.freeze

      # M3's verdicts that R3 dropped. Nothing sets them any more, but pull
      # requests labelled before R3 still carry them, so every new verdict
      # takes them off: otherwise #62's `review-passed` would sit beside its
      # next verdict, two at once. LabelSync never deletes them from the
      # repository; that stays a person's call.
      RETIRED = RENAMED.keys.freeze

      class << self
        # @return [Array<String>] every label name, in R3 order
        def names = ALL.map(&:name)

        # @return [Array<String>] every name a verdict replaces: R3's and {RETIRED}
        def known = names + RETIRED

        # @return [Array<ReviewLabel>] the verdicts refused while CI is red
        def passing = ALL.select(&:passing?)

        # The labels a new one takes off the pull request. Everything else in
        # the set, {RETIRED} included, except that setting {VULNERABILITY} leaves {REJECTED} where
        # it is, and setting {REJECTED} leaves {VULNERABILITY}: the two are
        # set as a pair, one call each, in either order.
        #
        # @param label [ReviewLabel]
        # @return [Array<String>]
        def displaced_by(label)
          kept = [label, *(PAIR if PAIR.include?(label))].map(&:name)
          known - kept
        end

        # @param name [String, ReviewLabel]
        # @return [ReviewLabel]
        # @raise [OpenLanes::Error] naming the valid labels
        def fetch(name)
          named(name.to_s) ||
            raise(Error, "unknown review label #{name.to_s.inspect}; one of: #{names.join(", ")}")
        end
      end

      # The two labels that may sit together.
      PAIR = [REJECTED, VULNERABILITY].freeze
    end
  end
end
