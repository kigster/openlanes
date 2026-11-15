# frozen_string_literal: true

module OpenLanes
  module Vcs
    # Check runs and commit statuses, mapped onto the buckets `gh pr checks`
    # reports, so {CiGate.verdict} reads every source alike. REST and GraphQL
    # spell the same values in different cases, so both are read downcased.
    module Buckets
      module_function

      # A check run as a bucket. An unlisted conclusion is a failure, as
      # {CiGate} treats an unknown bucket.
      #
      # @param status [String, nil] e.g. "completed", "IN_PROGRESS"
      # @param conclusion [String, nil] e.g. "success", "SKIPPED"
      # @return [String]
      def check_run(status, conclusion)
        return "pending" unless status.to_s.downcase == "completed"

        case conclusion.to_s.downcase
        when "success", "neutral" then "pass"
        when "skipped" then "skipping"
        else "fail"
        end
      end

      # A commit status as a bucket. `error`, and any state GitHub adds
      # later, is a failure.
      #
      # @param state [String, nil]
      # @return [String]
      def status(state)
        case state.to_s.downcase
        when "success" then "pass"
        when "pending", "expected" then "pending"
        else "fail"
        end
      end
    end
  end
end
