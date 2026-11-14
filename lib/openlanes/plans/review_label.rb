# frozen_string_literal: true

module OpenLanes
  module Plans
    # A label that says where a pull request stands in review (decision R3,
    # which replaced M3's set, and V2, which renamed one of R3's).
    #
    # A pull request carries one verdict at a time; a new verdict replaces
    # the previous one, with the exceptions {KEEPS} lists. Beside the verdict
    # sit two assessments, one label each: {RISK}, deploy-assessor's, and
    # {OPSEC}, security-reviewer's. This file is the only place under `lib/` that
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
        new(name: "review-rejected", colour: "F90000", meaning: "a reviewer rejected it", passing: false),
        # The harness's, never a reviewer's: a fix reached a rejected pull
        # request, by the publisher or by anyone else's push (decision U1).
        new(name: "review-addressed",
          colour: "A2FF02",
          meaning: "fixes were pushed after review-rejected; the PR waits for another review",
          passing: false),
        new(name: "review-passed", colour: "E8E890", meaning: "no reviewer rejected it, but most did not call it great", passing: true),
        new(name: "review-approved", colour: "109a10", meaning: "no reviewer rejected it, and most called it great", passing: true),
        new(name: "ready-to-merge",
          colour: "5319e7",
          meaning: "#{Agents::Names::VERIFIER} verified it and its E2E tests pass",
          passing: true),
        # What the engine did with a verified pull request (P2).
        new(name: "auto-merged",
          colour: "953384",
          meaning: "green, approved, low risk and cleared by security, so the engine merged it",
          passing: true),
        new(name: "merge-manually",
          colour: "0e8a16",
          meaning: "not approved, low risk and cleared by security all at once, or merge.by: human; a person merges it",
          passing: true)
      ].freeze

      # @param name [String]
      # @return [ReviewLabel]
      def self.named(name) = ALL.find { |l| l.name == name }

      # The label the publisher puts on a pull request it has just opened.
      INITIAL = named("ready-for-review")

      # What the engine puts on a pull request when its reviewers start.
      IN_PROGRESS = named("review-in-progress")

      # The verdict accepted even while CI is red.
      REJECTED = named("review-rejected")

      # The harness's label for a rejected pull request whose fixes arrived (U1).
      ADDRESSED = named("review-addressed")

      # The verdict for a review nobody rejected and most did not call great.
      PASSED = named("review-passed")

      # The verdict for a review most of the reviewers called great.
      APPROVED = named("review-approved")

      # verifier's label, and the one the coverage gate withholds.
      READY_TO_MERGE = named("ready-to-merge")

      # The engine merged it: green, and carrying all of {MERGEABLE}.
      AUTO_MERGED = named("auto-merged")

      # It lacks one of {MERGEABLE}, or `merge.by: human` keeps merging a person's.
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
      WAITING = [PASSED, APPROVED, READY_TO_MERGE, MERGE_MANUALLY].freeze

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

      # How likely deploying the pull request is to break production, as
      # deploy-assessor judged it. Not a verdict, and so not in {ALL}: one of
      # these sits beside the verdict, and a new one replaces the last.
      RISK = [
        new(name: "risk-low", colour: "0E8A16", meaning: "#{Agents::Names::DEPLOY_ASSESSOR}: deploying it is unlikely to break production", passing: true),
        new(name: "risk-medium", colour: "FBCA04", meaning: "#{Agents::Names::DEPLOY_ASSESSOR}: deploying it could break production", passing: false),
        new(name: "risk-high", colour: "D93F0B", meaning: "#{Agents::Names::DEPLOY_ASSESSOR}: deploying it is likely to break production", passing: false)
      ].freeze

      # The only risk the engine merges on.
      RISK_LOW = RISK.first

      # security-reviewer's own verdict. Not in {ALL} either: one of these
      # sits beside the review verdict, and a new one replaces the last.
      OPSEC = [
        new(name: "opsec-approved", colour: "1D76DB", meaning: "#{Agents::Names::SECURITY_REVIEWER} found nothing", passing: true),
        new(name: "opsec-concerned-approved",
          colour: "C5DEF5",
          meaning: "#{Agents::Names::SECURITY_REVIEWER} let it through with concerns a person should read",
          passing: false),
        new(name: "opsec-rejected", colour: "FF0050", meaning: "#{Agents::Names::SECURITY_REVIEWER} rejected it", passing: false)
      ].freeze

      # The only security verdict the engine merges on.
      OPSEC_APPROVED = OPSEC.first

      # What security-reviewer's rejection puts beside {REJECTED}.
      OPSEC_REJECTED = OPSEC.last

      # The two assessments that sit beside a verdict.
      FAMILIES = [RISK, OPSEC].freeze

      # The three labels the engine may merge a green pull request on. Any
      # other combination waits for a person.
      MERGEABLE = [APPROVED, RISK_LOW, OPSEC_APPROVED].freeze

      # Every label {Vcs::LabelSync} creates and recolours when a run starts.
      SYNCED = [*ALL, *RISK, *OPSEC, OPENLANES, CONFLICTS, CONFLICTS_RESOLVED].freeze

      # Not a verdict, and so not in {ALL}: {Vcs::LabelSync} never creates or
      # recolours it. Its presence on a repository is the one sign that
      # {Vcs::LabelMigration} has finished there. The colour of
      # `ready-to-merge` could not be that sign: an earlier release recoloured
      # it without moving a single pull request.
      MIGRATED = new(name: "openlanes-r3-labels",
        colour: "ededed",
        meaning: "openlanes moved this repository's open PRs from M3's review labels to R3's",
        passing: false)

      # R3's name for a verdict V2 renamed: `review-ok-not-perfect` is
      # {PASSED}. {Vcs::LabelSync} renames it on the repository, so the pull
      # requests carrying it keep it.
      # `review-vulnerability` said what {OPSEC_REJECTED} says now.
      RENAMED = { "review-ok-not-perfect" => PASSED, "review-vulnerability" => OPSEC_REJECTED }.freeze

      # M3's verifier label, R3's {READY_TO_MERGE} ({Vcs::LabelMigration}).
      OK_TO_MERGE = "ok-to-merge"

      # Verdict names no longer set. Pull requests labelled before a rename
      # may still carry them, so every new verdict takes them off: otherwise
      # an old `review-ok-not-perfect` would sit beside its next verdict, two
      # at once. LabelSync never deletes them from the repository; that stays
      # a person's call.
      RETIRED = [*RENAMED.keys, OK_TO_MERGE].freeze

      class << self
        # @return [Array<String>] every label name, in R3 order
        def names = ALL.map(&:name)

        # @return [Array<String>] every name a verdict replaces: R3's and {RETIRED}
        def known = names + RETIRED

        # @return [Array<String>] every name `openlanes review` takes: the
        #   verdicts, then {RISK} and {OPSEC}
        def settable = names + FAMILIES.flatten.map(&:name)

        # @param labels [Array<String>] what a pull request carries
        # @return [Array<String>] the names of {MERGEABLE} it lacks
        def unmergeable(labels) = MERGEABLE.map(&:name) - labels.map(&:to_s)

        # @return [Array<ReviewLabel>] the verdicts refused while CI is red
        def passing = ALL.select(&:passing?)

        # The labels a new one takes off the pull request. A verdict takes
        # off every other verdict, {RETIRED} included, except the ones
        # {KEEPS} lets it sit beside. A verdict that opens a new judgement
        # ({FRESH}) also takes off the last round's {RISK} and {OPSEC}; a
        # label of either family takes off only its own family.
        #
        # @param label [ReviewLabel]
        # @return [Array<String>]
        def displaced_by(label)
          family = FAMILIES.find { it.include?(label) }
          return (family - [label]).map(&:name) if family

          kept = [label, *KEEPS.fetch(label, [])].map(&:name)
          stale = FRESH.include?(label) ? FAMILIES.flatten.map(&:name) : []
          known - kept + stale
        end

        # @param name [String, ReviewLabel]
        # @return [ReviewLabel, nil] the {RISK} or {OPSEC} label of that name
        def beside(name) = FAMILIES.flatten.find { it.name == name.to_s }

        # @param name [String, ReviewLabel]
        # @return [ReviewLabel]
        # @raise [OpenLanes::Error] naming the valid labels
        def fetch(name)
          named(name.to_s) ||
            raise(Error, "unknown review label #{name.to_s.inspect}; one of: #{names.join(", ")}")
        end
      end

      # The verdicts a label is put beside rather than in place of. The
      # reviewers' passing verdict stays to the end, so the merge reads it
      # off the pull request ({MERGEABLE}); and a second group of reviewers
      # starting leaves what the first group said.
      KEEPS = [IN_PROGRESS, READY_TO_MERGE, AUTO_MERGED, MERGE_MANUALLY].to_h { [it, [PASSED, APPROVED]] }.freeze

      # The labels that open a new judgement of the pull request, so the
      # last one's {RISK} and {OPSEC} no longer describe it.
      FRESH = [INITIAL, ADDRESSED].freeze
    end
  end
end
