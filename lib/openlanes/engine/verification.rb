# frozen_string_literal: true

module OpenLanes
  module Engine
    # Running a reviewed pull request before it may merge (plan 014, M1).
    #
    # hansolo's approval moves the plan to 🧪 Verifying. The engine starts the
    # plan's app ({AppSession}), `chewie-verifier` follows the pull request's
    # `## How to test` against it and leaves screenshots and a report in a
    # {Round}'s folder, and the engine acts on the verdict ({Outcome}):
    # commit, comment, label, and the plan to 🔴, or green CI, the coverage
    # gate and `ready-to-merge`.
    module Verification
      # The phase an agent definition declares to be the verifier. Its
      # Completed notes are verdicts, as the review phase's are.
      PHASE = "verification"

      # The verdicts that go on to verification. Only `review-approved` for
      # now; `review-ok-not-perfect` joins it under `mvp` once plan 032
      # builds `desired_codebase_quality` (R4).
      FROM_REVIEW = [Plans::ReviewLabel::APPROVED].freeze

      module_function

      # @param plan_dir [String]
      # @return [Round] the round a new run of chewie works in
      def round_for(plan_dir) = Round.next(plan_dir)

      # @param plan_dir [String]
      # @return [Round, nil] the newest round
      def latest(plan_dir) = Round.latest(plan_dir)

      # @return [AppSession]
      def session(**) = AppSession.new(**)

      # @return [Outcome]
      def outcome(**) = Outcome.new(**)

      # @param labels [Array<String>] a pull request's labels
      # @return [Boolean] whether its review verdict goes on to verification
      def from_review?(labels) = FROM_REVIEW.any? { labels.include?(it.name) }
    end
  end
end
