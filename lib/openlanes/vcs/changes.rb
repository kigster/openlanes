# frozen_string_literal: true

require "open3"

module OpenLanes
  module Vcs
    # The files a plan's branch changes, read from its worktree with `git
    # diff`, so deciding whether a stage-2 reviewer is needed costs no
    # network call.
    class Changes
      # @param worktree [#path_for] where each plan's checkout lives
      # @param base [#call] `(path) -> String` the ref the branch is compared to
      def initialize(worktree:, base: ->(path) { "#{Refresh::REMOTE}/#{Refresh.default_branch(path)}" })
        @worktree = worktree
        @base = base
      end

      # @param subject [Plans::Subject]
      # @return [Array<String>, nil] paths relative to the repository root;
      #   nil when there is no checkout or git cannot say, which a reviewer
      #   reads as "watch it"
      def call(subject)
        path = @worktree.path_for(subject.feature)
        return nil unless File.directory?(path)

        out, status = Open3.capture2("git", "-C", path, "diff", "--name-only", "#{@base.call(path)}...HEAD", err: File::NULL)
        status.success? ? out.lines.map(&:strip).reject(&:empty?) : nil
      end
    end
  end
end
