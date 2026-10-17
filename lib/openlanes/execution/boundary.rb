# frozen_string_literal: true

require "shellwords"

module OpenLanes
  module Execution
    # The AFTER half of the autonomy boundary: what the checkout looked like
    # before an agent ran, and what crossing the line looks like afterwards.
    #
    # Two things are checked. HEAD must not move, because the boundary is docs
    # plus code and no commits. And no remote-tracking ref may have been moved
    # by a push, because a push is the one thing that leaves the machine.
    #
    # The push check reads only local state: `git push` updates the
    # remote-tracking ref of every branch it pushes (`refs/remotes/origin/x`)
    # and logs that update as "update by push". `git ls-remote` would also see
    # pushes made some other way (a URL instead of a remote name, the GitHub
    # API), but it costs a network round trip on every invocation, and it
    # cannot tell an agent's push from a teammate's, from CI, or from this
    # harness publishing another plan a second earlier, so it would fail
    # honest runs for other people's work. A check that cries wolf gets
    # turned off.
    #
    # Comparing tracking refs alone is not enough either: an agent that runs
    # `git fetch` moves them to whatever the remote already holds, and nothing
    # left the machine. So a ref that moved counts only when its reflog says a
    # push moved it during the run. A ref that moved with no reflog entry at all
    # (reflogs switched off) cannot be told apart from a push, and is reported.
    #
    # Worktrees share `refs/remotes`, so a push from any other checkout of
    # the repository (a person, another session, a sibling agent's harness)
    # moves the same refs during this run. A pushed commit that is the HEAD
    # of another worktree was pushed from there, and is not this agent's.
    #
    # Blind spots, by construction: a push to a bare URL updates no tracking
    # ref, and a deleted remote branch takes its tracking ref and that ref's
    # reflog with it, which locally looks the same as `git fetch --prune`.
    module Boundary
      # How `git push` signs the tracking refs it updates.
      PUSHED = "update by push"

      # What one checkout looked like before an agent ran in it.
      #
      # @!attribute [r] head
      #   @return [String, nil] nil outside a repository, which turns the check off
      # @!attribute [r] remotes
      #   @return [Hash{String => String}] remote-tracking ref to the commit it named
      # @!attribute [r] reflogs
      #   @return [Hash{String => Integer}] remote-tracking ref to how many
      #     reflog entries it had, so the entries the run added can be told
      #     from the ones before it. Counting, rather than comparing reflog
      #     timestamps, because those have one-second resolution and a
      #     publish in the same second as the snapshot would read as new.
      Snapshot = Data.define(:head, :remotes, :reflogs) do
        # @param root [String] the checkout the agent worked in
        # @return [String, nil] what boundary was crossed, or nil
        def violation(root)
          return nil if head.nil?

          after = Boundary.head(root)
          return "agent committed (HEAD moved #{head[0, 7]} → #{after.to_s[0, 7]}) — the boundary is docs plus code, no commits" if after != head

          pushed = Boundary.pushed(self, root)
          return nil if pushed.empty?

          "agent pushed (#{pushed.map { |ref| ref.delete_prefix("refs/remotes/") }.join(", ")}) — the boundary is docs plus code, nothing leaves the machine"
        end
      end

      @sanctioned = Hash.new { |hash, ref| hash[ref] = [] }
      @lock = Mutex.new

      class << self
        # @param root [String]
        # @return [OpenLanes::Execution::Boundary::Snapshot]
        def snapshot(root)
          Snapshot.new(head: head(root), remotes: remotes(root), reflogs: reflogs(root).transform_values(&:size))
        end

        # Records a push the harness itself is about to make, so an agent
        # running in another worktree of the same repository is not blamed
        # for it. Worktrees share `refs/remotes`, and the publisher pushes one
        # plan's branch while other agents are still working theirs.
        #
        # @param path [String] the checkout being pushed
        # @param remote [String]
        # @param branch [String]
        # @return [void]
        def sanction(path, remote, branch)
          sha = rev_parse(path, "refs/heads/#{branch}")
          return if sha.nil?

          @lock.synchronize { @sanctioned["refs/remotes/#{remote}/#{branch}"] << sha }
        end

        # @param ref [String]
        # @param sha [String]
        # @return [Boolean]
        def sanctioned?(ref, sha) = @lock.synchronize { @sanctioned.fetch(ref, []).include?(sha) }

        # For specs: forget every sanctioned push.
        #
        # @return [void]
        def reset! = @lock.synchronize { @sanctioned.clear }

        # @param root [String]
        # @return [String, nil] current commit, or nil outside a repository
        def head(root) = rev_parse(root, "HEAD")

        # The symbolic `refs/remotes/<remote>/HEAD` is left out: it moves with
        # `git remote set-head`, which pushes nothing.
        #
        # @param root [String]
        # @return [Hash{String => String}]
        def remotes(root)
          out = `git -C #{root.shellescape} for-each-ref --format='%(refname) %(objectname)' refs/remotes 2>/dev/null`
          out.lines.map(&:split).select { |pair| pair.size == 2 }.reject { |ref, _| ref.end_with?("/HEAD") }.to_h
        end

        # @param before [OpenLanes::Execution::Boundary::Snapshot]
        # @param root [String]
        # @return [Array<String>] tracking refs a push moved since the snapshot
        def pushed(before, root)
          logs = elsewhere = nil
          remotes(root).filter_map do |ref, sha|
            next if before.remotes[ref] == sha || sanctioned?(ref, sha)
            next if (elsewhere ||= other_heads(root)).include?(sha)

            logs ||= reflogs(root)
            entries = logs.fetch(ref, [])
            added = entries.first([entries.size - before.reflogs.fetch(ref, 0), 0].max)
            ref if added.empty? || added.any? { |reason| reason.start_with?(PUSHED) }
          end
        end

        # The commit checked out in every worktree of the repository but
        # +root+'s own: what a push from one of them would carry.
        #
        # @param root [String]
        # @return [Set<String>]
        def other_heads(root)
          own = real(rev_parse_path(root))
          out = `git -C #{root.shellescape} worktree list --porcelain 2>/dev/null`
          out.split("\n\n").each_with_object(Set.new) do |block, heads|
            fields = block.lines.to_h { |line| line.chomp.split(" ", 2) }
            heads << fields["HEAD"] if fields["HEAD"] && real(fields["worktree"]) != own
          end
        end

        private

        # @return [String, nil] the checkout's top level
        def rev_parse_path(root)
          out = `git -C #{root.shellescape} rev-parse --show-toplevel 2>/dev/null`.strip
          out.empty? ? root : out
        end

        # @return [String, nil] the path with symlinks resolved, as git prints it
        def real(path)
          File.realpath(path.to_s)
        rescue SystemCallError
          path
        end

        # @return [String, nil]
        def rev_parse(root, rev)
          out = `git -C #{root.shellescape} rev-parse --verify --quiet #{rev.shellescape} 2>/dev/null`.strip
          out.empty? ? nil : out
        end

        # Every remote-tracking ref's reflog, in one call.
        #
        # @return [Hash{String => Array<String>}] ref to why it moved, newest first
        def reflogs(root)
          out = `git -C #{root.shellescape} log --walk-reflogs --glob=refs/remotes --format=%gD%x09%gs 2>/dev/null`
          out.lines.each_with_object(Hash.new { |hash, ref| hash[ref] = [] }) do |line, logs|
            selector, reason = line.chomp.split("\t", 2)
            ref, index = selector.to_s.match(/\A(.+)@\{(\d+)\}\z/)&.captures
            logs[ref][index.to_i] = reason.to_s if ref
          end
        end
      end
    end
  end
end
