# frozen_string_literal: true

require "open3"

module OpenLanes
  module Web
    # A plan branch's changes against the default branch: `git diff --stat`
    # and the patch, read locally. The patch is capped, since a plan that
    # vendored a library would otherwise send megabytes to a page row.
    class BranchDiff
      # Bytes of patch sent before it is cut.
      MAX_PATCH = 200_000

      # What a diff says when there is no branch to read.
      EMPTY = { stat: "", patch: "", truncated: false }.freeze

      # @param root [String] the repository
      # @param base [String, nil] the branch diffed against; the remote's
      #   default, or main
      # @param max [Integer]
      def initialize(root:, base: nil, max: MAX_PATCH)
        @root = root
        @base = base
        @max = max
      end

      # @param feature [OpenLanes::Plans::Feature]
      # @return [Hash] `{ stat:, patch:, truncated: }`
      def call(feature)
        branch = branch_for(feature) or return EMPTY
        range = "#{base}...#{branch}"
        patch = git("diff", range).to_s
        { stat: git("diff", "--stat", range).to_s, patch: patch.byteslice(0, @max).scrub, truncated: patch.bytesize > @max }
      end

      private

      # The plan's branch, `<user>/<ordinal>-<slug>`, whoever the user is.
      #
      # @return [String, nil]
      def branch_for(feature)
        git("for-each-ref", "--format=%(refname:short)", "refs/heads/*/#{feature.ordinal}-#{feature.slug}").to_s.lines.first&.strip
      end

      # @return [String]
      def base = @base ||= Vcs::Refresh.default_branch(@root) || "main"

      # @return [String, nil] STDOUT, nil when git failed
      def git(*)
        out, status = Open3.capture2("git", "-C", @root, *, err: File::NULL)
        out if status.success?
      end
    end
  end
end
