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

      # The verdicts that go on to verification at every quality.
      FROM_REVIEW = [Plans::ReviewLabel::APPROVED].freeze

      # The verdict whose fate `desired_codebase_quality` decides (R4): on
      # to verification under `mvp`, back to luke and rey under `standard` and `high`.
      ON_QUALITY = Plans::ReviewLabel::OK_NOT_PERFECT

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
      # @param quality [Symbol, nil] {Config#desired_codebase_quality}; nil
      #   while the project is still to be asked, which lets nothing but
      #   {FROM_REVIEW} through
      # @return [Boolean] whether its review verdict goes on to verification
      def from_review?(labels, quality: nil)
        return true if FROM_REVIEW.any? { labels.include?(it.name) }

        quality == :mvp && labels.include?(ON_QUALITY.name)
      end

      # Under `mvp` an approved pull request is not run through chewie (plan
      # 035): CI and the coverage gate still stand between it and a merge.
      #
      # @param labels [Array<String>] a pull request's labels
      # @param quality [Symbol, nil] {Config#desired_codebase_quality}
      # @return [Boolean] whether its verdict skips verification
      def skips_verification?(labels, quality: nil) = quality == :mvp && FROM_REVIEW.any? { labels.include?(it.name) }

      # @param labels [Array<String>] a pull request's labels
      # @return [Boolean] whether the verdict is the one the quality decides
      def ok_not_perfect?(labels) = labels.include?(ON_QUALITY.name) && FROM_REVIEW.none? { labels.include?(it.name) }
    end
  end
end
