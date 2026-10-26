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
          meaning: "#{Agents::Names::BACKEND_CODER} and #{Agents::Names::FRONTEND_CODER} are done; the PR waits for a free review slot",
          passing: false),
        new(name: "review-in-progress", colour: "FFBE20", meaning: "the reviewers have started", passing: false),
        new(name: "review-rejected", colour: "F90000", meaning: "at least one ⛔️ or 💣", passing: false),
        new(name: "review-vulnerability",
          colour: "FF0050",
          meaning: "at least one 💣; sits beside review-rejected",
          passing: false),
        # The harness's, never a reviewer's: a fix reached a rejected pull
        # request, by the publisher or by anyone else's push (decision U1).
        new(name: "review-addressed",
          colour: "A2FF02",
          meaning: "fixes were pushed after review-rejected; the PR waits for another review",
          passing: false),
        new(name: "review-ok-not-perfect", colour: "E8E890", meaning: "no ⛔️ or 💣, but more 🤔 than review.max_hmm (5 by default)", passing: true),
        new(name: "review-approved", colour: "109a10", meaning: "no ⛔️ or 💣, few 🤔", passing: true),
        new(name: "ready-to-merge",
          colour: "5319e7",
          meaning: "#{Agents::Names::VERIFIER} verified it and its E2E tests pass",
          passing: true),
        # deploy-assessor's two verdicts, as the engine acted on them (P2).
        new(name: "auto-merged",
          colour: "953384",
          meaning: "#{Agents::Names::DEPLOY_ASSESSOR} judged it safe and the engine merged it",
          passing: true),
        new(name: "merge-manually",
          colour: "0e8a16",
          meaning: "#{Agents::Names::DEPLOY_ASSESSOR}, or merge.by: human, left it for a person to merge",
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

      # The harness's label for a rejected pull request whose fixes arrived (U1).
      ADDRESSED = named("review-addressed")

      # The verdict for a review with no ⛔️ or 💣 but too many 🤔.
      OK_NOT_PERFECT = named("review-ok-not-perfect")

      # The verdict for everything else.
      APPROVED = named("review-approved")

      # verifier's label, and the one the coverage gate withholds.
      READY_TO_MERGE = named("ready-to-merge")

      # The engine merged it on deploy-assessor's `auto`.
      AUTO_MERGED = named("auto-merged")

      # deploy-assessor said `manual`, or `merge.by: human` overrode its `auto`.
      MERGE_MANUALLY = named("merge-manually")

      # Either verdict: the pull request is complete (P2).
      COMPLETE = [AUTO_MERGED, MERGE_MANUALLY].freeze

      # Not a verdict, and so not in {ALL}, which a new verdict takes off: it
      # marks every pull request openlanes opened, and stays there. The
      # publisher adds it beside {INITIAL}, and {SYNCED} keeps its colour.
      OPENLANES = new(name: "openlanes",
        colour: "00FFFF",
        meaning: "opened by openlanes from a plan in .plans",
        passing: false)

      # Verdicts after which nobody works on a pull request until it merges,
      # so nothing but the conflict sweep notices it go stale against `main` (U2).
      WAITING = [OK_NOT_PERFECT, APPROVED, READY_TO_MERGE, MERGE_MANUALLY].freeze

      # Not a verdict, and so not in {ALL}: it sits beside whatever verdict
      # the pull request carries, which a resolved conflict keeps (U3).
      CONFLICTS = new(name: "conflicts",
        colour: "B60205",
        meaning: "no longer merges clean onto main; #{Agents::Names::REBASER} rebases it",
        passing: false)

      # What {CONFLICTS} becomes once the resolution is pushed (U3).
      CONFLICTS_RESOLVED = new(name: "conflicts-resolved",
        colour: "008B75",
        meaning: "a conflict with main was resolved and pushed; CI runs on the new head",
        passing: false)

      # Every label {Vcs::LabelSync} creates and recolours when a run starts.
      SYNCED = [*ALL, OPENLANES, CONFLICTS, CONFLICTS_RESOLVED].freeze

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
      # is R3's {OK_NOT_PERFECT}, and verifier's `ok-to-merge` is R3's
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
