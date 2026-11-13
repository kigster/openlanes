# frozen_string_literal: true

module OpenLanes
  module Web
    # What `GET /api/plans/:ordinal/review` answers: the plan branch's diff
    # and its reviewers' findings, each with its ruling (B3 in plan 064).
    class PlanReview
      # A plan number that names no plan.
      class NotFound < Error; end

      # @param plans_dir [String]
      # @param diff [#call] feature to `{ stat:, patch:, truncated: }`
      # @param findings [#for] plan folder to `Plans::Findings::Finding`s
      def initialize(plans_dir:, diff:, findings: Plans::Findings)
        @plans_dir = plans_dir
        @diff = diff
        @findings = findings
      end

      # @param ordinal [String]
      # @return [Hash] `{ diff:, findings: }`
      # @raise [NotFound]
      def call(ordinal)
        number = Plans::Ordinal.parse(ordinal.to_s) or raise NotFound, "#{ordinal} is not a plan number"
        subject = Plans.tree(@plans_dir).find(number) or raise NotFound, "there is no plan #{number}"
        { diff: @diff.call(subject.feature), findings: @findings.for(subject.feature.path).map(&:wire) }
      end
    end
  end
end
