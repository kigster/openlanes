# frozen_string_literal: true

require "open3"

module OpenLanes
  module Vcs
    # Brings one plan's worktree up to date with the default branch on
    # `origin`, before an agent runs in it.
    #
    # A worktree reused round after round never moved: plan 008.01's branch
    # had no commits of its own and sat 211 commits behind origin/main, so
    # luke-backend went looking for code that had landed weeks earlier and
    # could not find it. The agent could not catch up on its own either,
    # because the boundary fails every run in which HEAD moved. So the
    # harness moves HEAD, here, before {Execution::Boundary} takes its
    # snapshot, and the agent's HEAD check still holds.
    #
    # Three cases, by what the branch carries:
    #
    # - nothing of its own: fast-forward. No agent is ever involved.
    # - commits of its own, a clean tree: `git rebase`. A conflict leaves the
    #   rebase stopped for an agent to resolve; the harness continues it.
    # - uncommitted changes and commits of its own: left alone. Rebasing
    #   needs a clean tree, and `--autostash` can strand an agent's
    #   uncommitted work in the stash when it fails to re-apply, which is
    #   exactly the silent loss worktrees exist to prevent.
    #
    # Nothing here commits anything of its own; `rebase --continue` replays
    # commits that already exist, with the resolution an agent staged.
    class Refresh
      # The remote every plan branch is published to.
      REMOTE = "origin"

      # The default branch when `origin/HEAD` names none, as in a clone made
      # with `git init` and `remote add` rather than `git clone`.
      FALLBACK = "main"

      # How git says a staged file still holds a conflict marker. `diff
      # --check` also reports whitespace, which is no reason to stop a rebase.
      MARKER = "leftover conflict marker"

      # Seconds a fetch may take before it is abandoned. It runs on the
      # dispatcher's tick thread, so a fetch stuck on a credential prompt or
      # a stalled socket would stop every lane on the machine.
      FETCH_TIMEOUT = 60

      # git and ssh must fail rather than ask: nobody is there to answer.
      # BatchMode is appended to the user's own ssh command, not put in its
      # place, so a configured key or jump host still applies.
      #
      # @return [Hash{String => String}]
      def self.fetch_env
        { "GIT_TERMINAL_PROMPT" => "0", "GIT_SSH_COMMAND" => "#{ENV.fetch("GIT_SSH_COMMAND", "ssh")} -o BatchMode=yes" }
      end

      # What one refresh did.
      #
      # @!attribute [r] kind
      #   @return [Symbol] :current, :fast_forwarded, :rebased, :conflicted,
      #     :skipped, :pending or :aborted. Only :conflicted leaves a rebase
      #     stopped; a :skipped from {#continue} still has one, for the
      #     caller to abort
      # @!attribute [r] base
      #   @return [String, nil] e.g. "origin/main"
      # @!attribute [r] target
      #   @return [String, nil] the commit `base` named, so a retry can tell
      #     whether the default branch has moved since
      # @!attribute [r] commits
      #   @return [Integer] how many commits the branch was behind
      # @!attribute [r] files
      #   @return [Array<String>] the conflicted paths, when it stopped
      # @!attribute [r] reason
      #   @return [String, nil] why nothing happened, for :skipped and :pending
      Outcome = Data.define(:kind, :base, :target, :commits, :files, :reason) do
        def initialize(base: nil, target: nil, commits: 0, files: [], reason: nil, **rest) = super

        # @return [Boolean] the rebase is stopped, waiting on a resolution
        def conflicted? = kind == :conflicted

        # @return [Boolean] the branch now sits on the latest default branch
        def done? = %i[current fast_forwarded rebased].include?(kind)

        # One line for the progress log.
        #
        # @return [String]
        def summary
          case kind
          when :current then "worktree: up to date with #{base}"
          when :fast_forwarded then "worktree: fast-forwarded #{commits} commit#{"s" unless commits == 1} to #{base}"
          when :rebased then "worktree: rebased onto #{base} (#{commits} new upstream commit#{"s" unless commits == 1})"
          when :conflicted then "worktree: rebase onto #{base} stopped on conflicts in #{files.join(", ")}"
          when :aborted then "worktree: rebase onto #{base} aborted, branch restored: #{reason}"
          when :pending then "worktree: rebase onto #{base} pending: #{reason}"
          else "worktree: not refreshed: #{reason}"
          end
        end
      end

      class << self
        # The default branch, as `origin/HEAD` names it.
        #
        # @param path [String] any checkout of the repository
        # @return [String] e.g. "main"
        def default_branch(path)
          out, status = Open3.capture2("git",
            "-C",
            path,
            "symbolic-ref",
            "--quiet",
            "refs/remotes/#{REMOTE}/HEAD",
            err: File::NULL)
          name = out.strip.delete_prefix("refs/remotes/#{REMOTE}/")
          status.success? && !name.empty? ? name : FALLBACK
        end

        # Fetch the default branch, and say where a new branch should start.
        #
        # A fetch only moves `refs/remotes`, logged as a fetch rather than a
        # push, so {Execution::Boundary} does not blame an agent running in
        # another worktree for it.
        #
        # @param path [String]
        # @return [String, nil] "origin/<default>" once it exists, nil when
        #   the repository has no such remote branch
        def fetch(path)
          return nil unless system("git", "-C", path, "remote", "get-url", REMOTE, out: File::NULL, err: File::NULL)

          base = default_branch(path)
          fetched = fetch_within("git", "-C", path, "fetch", "--quiet", REMOTE, base)
          UI.log("worktree: could not fetch #{REMOTE} #{base}; working from the last fetch") unless fetched
          ref = "#{REMOTE}/#{base}"
          if system("git",
            "-C",
            path,
            "rev-parse",
            "--verify",
            "--quiet",
            "refs/remotes/#{ref}",
            out: File::NULL,
            err: File::NULL)
            ref
          end
        end

        private

        # Run a fetch, killing its whole process group (git, and the ssh or
        # credential helper it started) once it has run past {FETCH_TIMEOUT}.
        #
        # @return [Boolean] whether it finished, and succeeded, in time
        def fetch_within(*argv, timeout: FETCH_TIMEOUT, spawner: Spawner::System)
          pid = spawner.spawn(fetch_env, *argv, pgroup: true, in: File::NULL, out: File::NULL, err: File::NULL)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          loop do
            _, status = Process.wait2(pid, Process::WNOHANG)
            return status.success? if status
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            sleep 0.05
          end
          UI.log("worktree: git fetch timed out after #{timeout}s")
          begin
            Process.kill("KILL", -pid)
          rescue Errno::ESRCH, Errno::EPERM
            # Already gone, or not ours to end.
          end
          Process.wait(pid)
          false
        end
      end

      # @param path [String] the plan's worktree
      def initialize(path:) = @path = path

      # @return [String]
      attr_reader :path

      # Fetch, then fast-forward or rebase onto the default branch.
      #
      # @param hold [String, nil] a default-branch commit the rebase has
      #   already failed on as often as it may: while `origin/<default>` still
      #   names it, a branch that would need a rebase is left where it is
      # @return [OpenLanes::Vcs::Refresh::Outcome]
      def call(hold: nil)
        return resume if rebasing?

        base = self.class.fetch(path) or return Outcome.new(kind: :skipped, reason: "no #{REMOTE} default branch")
        target = rev(base)
        behind = count("HEAD..#{base}")
        return Outcome.new(kind: :current, base:, target:) if behind.zero?
        return fast_forward(base, target, behind) if count("#{base}..HEAD").zero?

        outcome = Outcome.new(kind: :skipped, base:, target:, commits: behind)
        return outcome.with(reason: "uncommitted changes in the worktree") if dirty?
        return outcome.with(kind: :pending, reason: "retries exhausted until #{base} moves") if hold == target

        rebase(base, target, behind)
      end

      # Carry a stopped rebase on, once an agent has resolved and staged.
      #
      # Refused while any path is unmerged or a staged file still holds a
      # marker: continuing then would commit the marker into the branch.
      #
      # @return [OpenLanes::Vcs::Refresh::Outcome] :rebased, or :conflicted
      #   on the files that still need a resolution (the same commit's, or
      #   the next one's)
      def continue
        base = onto
        left = unresolved
        return Outcome.new(kind: :conflicted, base:, target: rev(base), files: left) unless left.empty?

        # A resolution identical to what is already on HEAD leaves the commit
        # empty. Newer git drops it on continue, older git refuses and is
        # skipped past. Either way it drops nothing the branch still needs
        # (the index is HEAD), but the commit is gone, so it is named.
        empty = git({}, "diff", "--cached", "--quiet")
        stopped_at = capture("log", "-1", "--format=%h %s", "REBASE_HEAD") if empty
        ok = git({ "GIT_EDITOR" => "true" }, "rebase", "--continue")
        ok ||= empty && rebasing? && unmerged.empty? && git({}, "rebase", "--skip")
        dropped(stopped_at, base)
        stopped = rebasing? ? unmerged : []
        return Outcome.new(kind: :conflicted, base:, target: rev(base), files: stopped) unless stopped.empty?
        return Outcome.new(kind: :rebased, base:, target: rev(base)) if ok && !rebasing?

        # Stopped with nothing to resolve (a hook refused, say): no agent can
        # help, so the caller aborts.
        Outcome.new(kind: :skipped, base:, reason: "git rebase --continue failed with nothing unmerged")
      end

      # Abandon a stopped rebase. git puts the branch back exactly where it
      # was before the rebase began.
      #
      # @param why [String]
      # @return [OpenLanes::Vcs::Refresh::Outcome]
      def abort!(why)
        base = onto
        git({}, "rebase", "--abort") if rebasing?
        Outcome.new(kind: :aborted, base:, target: rev(base), reason: why)
      end

      # @return [Boolean] whether a rebase is stopped in this worktree
      def rebasing? = %w[rebase-merge rebase-apply].any? { File.directory?(git_path(it)) }

      # @return [Array<String>] paths git still lists as unmerged
      def unmerged = lines("diff", "--name-only", "--diff-filter=U")

      # Unmerged paths, and staged files that still hold a conflict marker.
      #
      # @return [Array<String>]
      def unresolved
        marked = lines("diff", "--cached", "--check").filter_map { |line| line.split(":", 2).first if line.include?(MARKER) }
        (unmerged + marked).uniq
      end

      private

      # A rebase found stopped before anyone asked: a harness that died
      # mid-resolution, or a round that ended before it continued. It is
      # picked up where it stood rather than started again.
      #
      # @return [OpenLanes::Vcs::Refresh::Outcome]
      def resume
        left = unresolved
        return Outcome.new(kind: :conflicted, base: onto, target: rev(onto), files: left) unless left.empty?

        continue
      end

      # @return [OpenLanes::Vcs::Refresh::Outcome]
      def fast_forward(base, target, behind)
        # Safe with uncommitted changes: git refuses, touching nothing, when
        # one of them is in a file the merge would change.
        return Outcome.new(kind: :fast_forwarded, base:, target:, commits: behind) if git({}, "merge", "--ff-only", "--quiet", base)

        Outcome.new(kind: :skipped,
          base:,
          target:,
          commits: behind,
          reason: "fast-forward refused; uncommitted changes touch files #{base} changed")
      end

      # @return [OpenLanes::Vcs::Refresh::Outcome]
      def rebase(base, target, behind)
        return Outcome.new(kind: :rebased, base:, target:, commits: behind) if git({ "GIT_EDITOR" => "true" }, "rebase", "--quiet", base)
        return Outcome.new(kind: :conflicted, base:, target:, commits: behind, files: unresolved) if rebasing?

        Outcome.new(kind: :skipped, base:, target:, commits: behind, reason: "git rebase refused to start")
      end

      # The branch the stopped rebase is replaying onto, as a name.
      #
      # @return [String]
      def onto
        sha = File.read(git_path("rebase-merge/onto")).strip if File.file?(git_path("rebase-merge/onto"))
        base = "#{REMOTE}/#{self.class.default_branch(path)}"
        sha.nil? || rev(base) == sha ? base : sha[0, 7]
      end

      # Log a commit the rebase replayed as empty, once it is past it.
      #
      # @param stopped_at [String, nil] "<sha> <subject>" of the commit
      # @param base [String]
      # @return [void]
      def dropped(stopped_at, base)
        return if stopped_at.nil?
        return if rebasing? && capture("log", "-1", "--format=%h %s", "REBASE_HEAD") == stopped_at

        UI.log("worktree: rebase dropped #{stopped_at}: its changes are already on #{base}")
      end

      # @return [Boolean]
      def dirty? = !lines("status", "--porcelain").empty?

      # @return [Integer]
      def count(range) = capture("rev-list", "--count", range).to_i

      # @return [String, nil]
      def rev(ref) = capture("rev-parse", "--verify", "--quiet", ref).then { it.empty? ? nil : it }

      # @return [String] a path inside this worktree's own git directory
      def git_path(name) = File.expand_path(capture("rev-parse", "--git-path", name), path)

      # @return [Array<String>]
      def lines(*) = capture(*).lines(chomp: true).reject(&:empty?)

      # @return [String]
      def capture(*)
        out, = Open3.capture2("git", "-C", path, *, err: File::NULL)
        out.strip
      end

      # @return [Boolean]
      def git(env, *) = system(env, "git", "-C", path, *, out: File::NULL, err: File::NULL)
    end
  end
end
