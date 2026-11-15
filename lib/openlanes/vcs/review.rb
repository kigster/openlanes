# frozen_string_literal: true

module OpenLanes
  module Vcs
    # Moves a pull request from one review label to the next (M3, R3).
    #
    # The only way a review label is set: `gh pr edit` stays forbidden to
    # agents (L3), so the CI rule below cannot be skipped by labelling by hand
    # from inside a round.
    class Review
      # What happened, or under a dry run what would have.
      Result = Data.define(:pr, :from, :to, :ci, :refused, :reason, :dry_run) do
        alias_method :refused?, :refused
        alias_method :dry_run?, :dry_run
      end

      # `github:` defaults to the container's client, so a caller may pass
      # its own and a spec may stub the key instead.
      include Deps["github"]

      # @param pr [String, Integer] "12", "#12" or a pull request URL
      # @param label [String] a {Plans::ReviewLabel} name
      # @param dry_run [Boolean] compute the result, write nothing
      # @return [Result]
      # @raise [OpenLanes::Error] on an unknown label or a reference naming no
      #   pull request, before any `gh` call
      def call(pr:, label:, dry_run: false) # rubocop:disable Naming/MethodParameterName -- `pr` is the contract with CLI::Review
        to, scope = target(label)
        number = GitHub.number_of(pr)
        repo = GitHub.repo_of(pr)

        from = @github.labels(number:, repo:) & scope
        ci = CiGate.verdict(@github.checks(number:, repo:))
        reason = refusal(to, ci)
        result = Result.new(pr: number,
          from:,
          to: to.name,
          ci:,
          refused: !reason.nil?,
          reason: reason || (ci == :none ? NO_CHECKS : nil),
          dry_run:)
        return result if result.refused? || dry_run

        @github.swap_label(number:, repo:, add: to, remove: from & Plans::ReviewLabel.displaced_by(to))
        result
      end

      # Takes `review-in-progress` off, adding nothing: a group of reviewers
      # gave its verdict and no verdict label could say so, or the pull
      # request was merged or closed under them.
      #
      # @param pr [String, Integer]
      # @return [Boolean] whether the label was there to take off
      # @raise [OpenLanes::Error]
      def finish(pr:) # rubocop:disable Naming/MethodParameterName -- as {#call}
        number = GitHub.number_of(pr)
        repo = GitHub.repo_of(pr)
        name = Plans::ReviewLabel::IN_PROGRESS.name
        return false unless @github.labels(number:, repo:).include?(name)

        @github.remove_label(number:, name:, repo:)
        true
      end

      # Zero checks, or only skipped ones, counts as green (open question 2),
      # said out loud.
      NO_CHECKS = "no CI checks ran; treated as green"

      private

      # A verdict, or one of the assessments that sit beside it.
      #
      # @param name [String]
      # @return [Array(Plans::ReviewLabel, Array<String>)] the label, and the
      #   names it may replace: every verdict and assessment, or its own family
      # @raise [OpenLanes::Error] on an unknown label
      def target(name)
        beside = Plans::ReviewLabel.beside(name)
        return [beside, Plans::ReviewLabel.displaced_by(beside)] if beside

        [Plans::ReviewLabel.fetch(name), Plans::ReviewLabel.known + Plans::ReviewLabel::FAMILIES.flatten.map(&:name)]
      end

      # An assessment says what its assessor found, whatever CI says.
      #
      # @return [String, nil] why `to` may not be set now
      def refusal(label, verdict)
        return if !label.passing? || Plans::ReviewLabel.beside(label.name)

        case verdict
        when :red then "CI is red"
        when :pending then "CI pending"
        end
      end
    end
  end
end
