# frozen_string_literal: true

module OpenLanes
  module Vcs
    # Moves the open pull requests that still carry M3's review labels onto
    # R3's, once per repository, before anything reads a label in R3's sense.
    #
    # Under M3 `ready-to-merge` was a review verdict, "passed with nothing
    # open"; under R3 it is verifier's, and the merge gate reads it as
    # "verified". Left on a pull request no verifier ever saw, it would be
    # read as a verification that never happened. So it goes back to
    # `review-approved`, and a pull request verifier did verify earns it again
    # from the coverage gate: an ambiguous label is re-checked, never trusted.
    # M3's two other names map straight across ({Plans::ReviewLabel::RENAMED}).
    #
    # The steps run in order, and a pull request that carries `ok-to-merge`
    # is left out of the first two: the third puts `ready-to-merge` on it and
    # leaves `ok-to-merge` where it is, so a run interrupted after the third
    # step cannot read the `ready-to-merge` it just put there as M3's and take
    # it off again. `ok-to-merge` comes off once the migration is marked done.
    #
    # Done is a label on the repository, {Plans::ReviewLabel::MIGRATED},
    # created after the last step and never touched by {LabelSync}. Not the
    # colour of `ready-to-merge`: an earlier release recoloured that without
    # moving a pull request, which made the old meaning look migrated on
    # every repository it had run on. Nothing is kept on this machine, so a
    # second machine starting on the same repository agrees.
    class LabelMigration
      # Every open pull request carrying +from+ moves to +to+.
      Step = Data.define(:from, :to) do
        # @return [String]
        def to_s = "#{from} → #{to}"
      end

      # M3's verifier verification, kept beside `ready-to-merge` until the end.
      VERIFIED = "ok-to-merge"

      STEPS = [
        Step.new(from: Plans::ReviewLabel::READY_TO_MERGE.name, to: Plans::ReviewLabel::APPROVED),
        *Plans::ReviewLabel::RENAMED.map { |from, to| Step.new(from:, to:) }
      ].freeze

      # What the migration did, or under a dry run would do.
      #
      # @!attribute [r] pending
      #   @return [Boolean] whether the repository was not yet migrated
      # @!attribute [r] moves
      #   @return [Hash{Step => Array<Integer>}] each step's pull request numbers
      Outcome = Data.define(:pending, :moves) do
        alias_method :pending?, :pending

        # @return [Array<Integer>] every pull request relabelled, in step order
        def relabelled = moves.values.flatten

        # @return [String, nil] one line for the startup notice; nil when nothing moved
        def to_s
          return if relabelled.empty?

          "relabel #{moves.map { |step, numbers| "#{step} on #{numbered(numbers)}" }.join("; ")}"
        end

        private

        # @param numbers [Array<Integer>]
        # @return [String] "#7, #9"
        def numbered(numbers) = numbers.map { "##{it}" }.join(", ")
      end

      # @param github [GitHub]
      def initialize(github: GitHub.new)
        @github = github
      end

      # @param repo [String, nil] "owner/repo"; nil means the current checkout's
      # @param dry_run [Boolean] read the pull requests, relabel none, mark nothing
      # @return [Outcome]
      # @raise [OpenLanes::Error] when `gh` cannot list or relabel; the
      #   repository stays unmarked, so the next start tries again
      def call(repo: nil, dry_run: false)
        return Outcome.new(pending: false, moves: {}) if done?(repo)

        moves = STEPS.to_h { [it, move(it, repo:, dry_run:)] }.reject { |_, numbers| numbers.empty? }
        finish(repo) unless dry_run
        Outcome.new(pending: true, moves:)
      end

      private

      # @return [Boolean]
      def done?(repo) = @github.label_colours(repo:).key?(Plans::ReviewLabel::MIGRATED.name)

      # @param step [Step]
      # @return [Array<Integer>] the pull requests moved, or under a dry run to be
      def move(step, repo:, dry_run:)
        numbers = @github.open_pulls_labelled(step.from, repo:).reject { |_, labels| held?(step, labels) }.keys
        return numbers if dry_run || numbers.empty?

        @github.ensure_label(step.to, repo:)
        remove = Plans::ReviewLabel.displaced_by(step.to) - [VERIFIED]
        numbers.each { @github.swap_label(number: it, add: step.to, remove:, repo:, create_missing: false) }
        numbers
      end

      # Whether a pull request waits for the `ok-to-merge` step instead.
      #
      # @param step [Step]
      # @param labels [Array<String>]
      # @return [Boolean]
      def held?(step, labels) = step.from != VERIFIED && labels.include?(VERIFIED)

      # Mark the repository done, then take `ok-to-merge` off. The mark first:
      # once `ok-to-merge` is gone a `ready-to-merge` beside it is no longer
      # told apart from M3's. Taking it off is tidying, so it may fail: the
      # next verdict on that pull request takes it off anyway.
      #
      # @return [void]
      def finish(repo)
        @github.ensure_label(Plans::ReviewLabel::MIGRATED, repo:)
        tidy(repo)
      end

      # @return [void]
      def tidy(repo)
        @github.open_pulls_labelled(VERIFIED, repo:).each_key do |number|
          @github.swap_label(number:, add: Plans::ReviewLabel::READY_TO_MERGE, remove: [VERIFIED], repo:, create_missing: false)
        end
      rescue Error => e
        UI.log("#{VERIFIED} left on open pull requests: #{e.message}", level: :warn)
      end
    end
  end
end
