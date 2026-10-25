# frozen_string_literal: true

require "open3"

module OpenLanes
  module Vcs
    # The checkout a command that reads every plan should stand in: the
    # primary one, not a linked worktree, on the mainline branch, and current
    # with its upstream. A plan worktree's `.plans` is a snapshot the harness
    # overwrites when it publishes, so a run that writes keys there writes them nobody
    # keeps, and one on a feature branch reads plans `main` has
    # already moved past. Both are warned about rather than refused (008.01
    # D1): a person may have a reason, and the warning tells them the cost.
    class Mainline
      # @return [String]
      attr_reader :root, :branch

      # A pull that wants a password must fail, not wait on a prompt: under
      # `--stay` or mprocs nobody is at the terminal to answer it.
      PULL_ENV = { "GIT_TERMINAL_PROMPT" => "0" }.freeze

      # What git says when a pull would clobber local edits, most often the
      # uncommitted spec.md changes.
      DIRTY = /would be overwritten|uncommitted changes|unstaged changes/

      # @param root [String] repository root
      # @param branch [String, nil] the branch the command must run on; nil
      #   reads it from `origin/HEAD`, and falls back to `main`
      def initialize(root:, branch: nil)
        @root = root
        @branch = branch || default_branch
      end

      # @return [Boolean] whether {#root} is inside a git checkout at all
      def repository? = !git("rev-parse", "--git-dir").nil?

      # A linked worktree's git dir is `.git/worktrees/<name>`; only the
      # primary checkout's equals the common dir.
      #
      # @return [Boolean]
      def primary?
        dir = git("rev-parse", "--absolute-git-dir")
        common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
        !dir.nil? && File.realpath(dir) == File.realpath(common.to_s)
      rescue Errno::ENOENT
        false
      end

      # @return [String, nil] the checked-out branch, nil on a detached HEAD
      def current = git("symbolic-ref", "--quiet", "--short", "HEAD")

      # @return [Boolean]
      def on_branch? = current == branch

      # @return [Boolean] the primary checkout, on {#branch}
      def mainline? = primary? && on_branch?

      # @return [Array<String>] each guard that failed, empty when both hold
      def warnings
        return ["#{root} is not a git checkout; nothing to pull, and nothing keeps the keys written here"] unless repository?

        out = []
        out << "#{root} is a linked worktree; keys written here are lost unless this branch merges" unless primary?
        out << "on branch #{current || "(detached HEAD)"}, not #{branch}; linking against plans #{branch} may have moved past" unless on_branch?
        out
      end

      # Fast-forwards from the upstream. No upstream is not a failure: a
      # repository that was never pushed has nothing newer to pull.
      #
      # @return [Boolean] false when the pull ran and failed (diverged, offline)
      def pull
        upstream = git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
        if upstream.nil? || upstream.empty?
          @note = "#{branch} has no upstream; nothing pulled"
          return true
        end

        _, err, status = Open3.capture3(PULL_ENV, "git", "-C", root, "pull", "--ff-only", "--quiet")
        @note = status.success? ? "pulled #{upstream}" : failure(err.strip)
        status.success?
      end

      # @return [String, nil] what the last {#pull} did
      attr_reader :note

      private

      # @param err [String] git's STDERR
      # @return [String]
      def failure(err)
        note = "git pull --ff-only failed: #{err}"
        err.match?(DIRTY) ? "#{note}\ncommit the spec.md edits from the last link first, then run it again" : note
      end

      # @return [String] what `origin/HEAD` points at, `main` when unset
      def default_branch = git("symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")&.delete_prefix("origin/") || "main"

      # @return [String, nil] stripped STDOUT, nil when git failed
      def git(*)
        out, _, status = Open3.capture3("git", "-C", root, *)
        status.success? ? out.strip : nil
      end
    end
  end
end
