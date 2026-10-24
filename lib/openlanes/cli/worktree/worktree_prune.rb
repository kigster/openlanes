# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes worktree prune` — remove the plan worktrees whose pull
    # request merged into the default branch and whose work landed with it.
    #
    # The engine retires a plan's checkout as it sees the merge (see
    # {Engine::Merging}). This is for the ones it never saw: a run that
    # crashed, a merge made while no engine was up, checkouts from before
    # retirement existed. The rules are {Vcs::Worktree#retire}'s, so a
    # checkout with uncommitted work, unmerged commits or somebody's lock
    # in it stays, and the table says why.
    class WorktreePrune < Base
      desc "Remove plan worktrees whose pull request merged and whose work is on main"

      dry_run_option "Remove nothing; print what would be removed and why the rest stay"

      example [
        "                            # remove every worktree whose work landed",
        "-n                          # show what would be removed, and why the rest stay"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        worktree = OpenLanes::Vcs.worktree(root: OpenLanes::Vcs::Worktree.main_root(File.dirname(tree_for(options).dir)))
        refuse("#{worktree.root} is not a git repository", 66) unless worktree.repository?

        github = OpenLanes::Vcs.github
        locks = OpenLanes::Engine.agent_locks(worktree.root)
        held = ->(path) { locks&.held_in(path)&.to_s }
        rows = worktree.list.map { row(worktree, github, it, held, dry_run?(options)) }
        return UI.line("No plan worktrees under #{worktree.dir}.") if rows.empty? && !quiet?(options)

        puts table([%w[WORKTREE BRANCH PR RESULT], *rows]) unless quiet?(options)
        return unless dry_run?(options)

        count = rows.count { it.last.start_with?("would be removed") }
        dry_run_footer(count, "removal#{"s" unless count == 1}")
      end

      private

      # @return [Array<String>] one table row
      def row(worktree, github, path, held, dry_run)
        name = File.basename(path)
        branch = worktree.branch_of(path)
        return [name, "(detached)", "", "kept: detached HEAD, no branch to match a pull request"] if branch.empty?

        pull = github.merged_pull_for(branch)
        return [name, branch, "", "kept: no merged pull request"] unless pull

        retired = worktree.retire(path, merge_commit: pull[:merge_commit], base: pull[:base], held:, dry_run:)
        [name, branch, "##{pull[:number]}", result(retired)]
      rescue OpenLanes::Error => e
        [name, branch.to_s, "", "kept: #{e.message.lines.first.to_s.strip}"]
      end

      # @param retired [OpenLanes::Vcs::Worktree::Retirement]
      # @return [String]
      def result(retired)
        return "removed (#{retired.sha[0, 8]}): #{retired.reason}" if retired.removed?
        return retired.reason if retired.reason.start_with?("would be removed")

        "kept: #{retired.reason}"
      end

      # @param rows [Array<Array<String>>]
      # @return [String]
      def table(rows)
        widths = rows.transpose.map { |column| column.map { it.to_s.length }.max }
        rows.map { |row| row.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join("  ").rstrip }.join("\n")
      end
    end
  end
end
