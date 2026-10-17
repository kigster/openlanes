# frozen_string_literal: true

module OpenLanes
  module Vcs
    # Moves M3's `ready-to-merge` off the open pull requests that still carry
    # it, onto `review-approved` (R3), before {LabelSync} gives the label its
    # new meaning.
    #
    # Under M3 `ready-to-merge` was a review verdict, "passed with nothing
    # open"; under R3 it is chewie-verifier's, and the merge gate reads it as
    # "verified". Left on a pull request no verifier ever saw, it would be
    # read as a verification that never happened.
    #
    # The marker that the migration is still owed is the repository's own
    # label: while `ready-to-merge` exists in any colour but R3's, the meaning
    # is M3's. {LabelSync} recolours it only after this has run, so a run
    # interrupted half way leaves the colour alone and the next start finishes
    # the job: the pull requests already moved carry `ready-to-merge` no
    # longer, and are not asked about again. Once the colour is R3's the
    # migration never runs again, so a `ready-to-merge` chewie puts on later
    # is left where it is. Nothing is kept on this machine, so a second
    # machine starting on the same repository agrees.
    class LabelMigration
      # What the migration did, or under a dry run would do.
      #
      # @!attribute [r] pending
      #   @return [Boolean] whether the repository still had M3's meaning
      # @!attribute [r] relabelled
      #   @return [Array<Integer>] pull request numbers moved to `review-approved`
      Outcome = Data.define(:pending, :relabelled) do
        alias_method :pending?, :pending

        # @return [String, nil] one line for the startup notice; nil when nothing moved
        def to_s
          return if relabelled.empty?

          numbers = relabelled.map { "##{it}" }.join(", ")
          "relabel #{Plans::ReviewLabel::READY_TO_MERGE} → #{Plans::ReviewLabel::APPROVED} on #{numbers}"
        end
      end

      # @param github [GitHub]
      def initialize(github: GitHub.new)
        @github = github
      end

      # @param repo [String, nil] "owner/repo"; nil means the current checkout's
      # @param dry_run [Boolean] read the pull requests, relabel none
      # @return [Outcome]
      # @raise [OpenLanes::Error] when `gh` cannot list or relabel, which
      #   leaves the label's colour M3's, so the next start tries again
      def call(repo: nil, dry_run: false)
        return Outcome.new(pending: false, relabelled: []) unless pending?(repo)

        numbers = @github.open_pulls_labelled(old.name, repo:)
        unless dry_run
          numbers.each { @github.swap_label(number: it, add: approved, remove: Plans::ReviewLabel.displaced_by(approved), repo:) }
        end
        Outcome.new(pending: true, relabelled: numbers)
      end

      private

      # A repository without the label has no pull request carrying it, and
      # one with R3's colour has been migrated already.
      #
      # @return [Boolean]
      def pending?(repo)
        colour = @github.label_colours(repo:)[old.name]
        !colour.nil? && !colour.casecmp?(old.colour)
      end

      def old = Plans::ReviewLabel::READY_TO_MERGE
      def approved = Plans::ReviewLabel::APPROVED
    end
  end
end
