# frozen_string_literal: true

require "open3"

module OpenLanes
  module Vcs
    # How many lines a branch changes against the default branch: insertions
    # plus deletions from `git diff --shortstat <base>...HEAD`. Local refs
    # only, no fetch, because it is asked before an agent starts and a
    # network call there would cost every invocation a round trip.
    module DiffSize
      module_function

      # @param root [String] the checkout
      # @param base [String, nil] the ref to diff against; nil takes
      #   `origin/<default branch>`
      # @return [Integer, nil] nil when git cannot say, and then nothing is
      #   decided on size
      def lines(root, base: nil)
        base ||= "#{Refresh::REMOTE}/#{Refresh.default_branch(root)}"
        out, status = Open3.capture2("git", "-C", root, "diff", "--shortstat", "#{base}...HEAD", err: File::NULL)
        return nil unless status.success?

        out.scan(/(\d+) (?:insertion|deletion)/).sum { it.first.to_i }
      rescue SystemCallError
        nil
      end
    end
  end
end
