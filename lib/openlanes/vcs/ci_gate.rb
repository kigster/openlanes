# frozen_string_literal: true

module OpenLanes
  module Vcs
    # One word for a pull request's CI, from `gh pr checks` buckets (M3).
    module CiGate
      # Buckets that say nothing about the code: a skipped job is not a verdict.
      NEUTRAL = %w[pass skipping].freeze

      module_function

      # An unknown bucket counts as red (open question 5): a state `gh` grows
      # later must not wave a passing label through.
      #
      # @param checks [Array<Hash>] `{name:, bucket:}`, as {GitHub#checks} returns
      # @return [Symbol] `:green`, `:red`, `:pending`, or `:none` when no
      #   check ran
      def verdict(checks)
        buckets = checks.map { |c| c[:bucket].to_s }
        # Every job skipped means CI did not run (a spent Actions budget can
        # report it this way), which is the same as no checks, not a pass.
        return :none if buckets.all?("skipping")

        return :red if buckets.any? { |b| b != "pending" && !NEUTRAL.include?(b) }
        return :pending if buckets.include?("pending")

        :green
      end
    end
  end
end
