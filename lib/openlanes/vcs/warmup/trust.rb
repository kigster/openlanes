# frozen_string_literal: true

require "open3"

module OpenLanes
  module Vcs
    class Warmup
      # Whether a checkout may be installed by the harness. Installing runs
      # code the branch controls, outside the agent's boundary, so the answer
      # is yes only for what the base branch already holds.
      module Trust
        module_function

        # Whether the worktree's copy of `file` is the one on `base`, compared
        # by blob id, so an uncommitted or untracked edit counts as a change.
        #
        # @param path [String] the checkout
        # @param file [String] relative to it
        # @param base [String] a ref
        # @return [Boolean]
        def same_as_base?(path, file, base)
          local = File.join(path, file)
          return !git?(path, "cat-file", "-e", "#{base}:#{file}") unless File.file?(local)

          theirs, ok = Open3.capture2("git", "-C", path, "rev-parse", "--verify", "--quiet", "#{base}:#{file}", err: File::NULL)
          ours, = Open3.capture2("git", "-C", path, "hash-object", "--", file, err: File::NULL)
          ok.success? && theirs.strip == ours.strip
        end

        # Whether every file in the checkout, tracked or not, is the one on
        # `base`. The lockfile alone is not enough: `bundle check` evaluates the
        # `gemspec` a Gemfile names, its `eval_gemfile` includes and its `path:`
        # gems, and npm reads `.npmrc`, any of which an agent can edit. Only a
        # tree the branch has not touched is installed by the harness; anything
        # else is left to the agent, inside its own boundary.
        #
        # @param path [String] the checkout
        # @param base [String] a ref
        # @return [Boolean]
        def pristine?(path, base)
          return false unless git?(path, "diff", "--quiet", base, "--")

          untracked, ok = Open3.capture2("git", "-C", path, "ls-files", "--others", "--exclude-standard", err: File::NULL)
          ok.success? && untracked.strip.empty?
        end

        # @return [Boolean] whether `git -C path *args` succeeded
        def git?(path, *) = system("git", "-C", path, *, out: File::NULL, err: File::NULL)
      end
    end
  end
end
