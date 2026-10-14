# frozen_string_literal: true

module OpenLanes
  module Vcs
    # Moves a pull request from one review label to the next (M3).
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

      # @param github [GitHub]
      def initialize(github: GitHub.new)
        @github = github
      end

      # @param pr [String, Integer] "12", "#12" or a pull request URL
      # @param label [String] a {Plans::ReviewLabel} name
      # @param dry_run [Boolean] compute the result, write nothing
      # @return [Result]
      # @raise [OpenLanes::Error] on an unknown label or a reference naming no
      #   pull request, before any `gh` call
      def call(pr:, label:, dry_run: false) # rubocop:disable Naming/MethodParameterName -- `pr` is the contract with CLI::Review
        to = Plans::ReviewLabel.fetch(label)
        number = GitHub.number_of(pr)
        repo = GitHub.repo_of(pr)

        from = @github.labels(number:, repo:) & Plans::ReviewLabel.names
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

        @github.swap_label(number:, repo:, add: to, remove: from)
        result
      end

      # Zero checks, or only skipped ones, counts as green (open question 2),
      # said out loud.
      NO_CHECKS = "no CI checks ran; treated as green"

      private

      # @return [String, nil] why `to` may not be set now
      def refusal(label, verdict)
        return unless label.passing?

        case verdict
        when :red then "CI is red"
        when :pending then "CI pending"
        end
      end
    end
  end
end
