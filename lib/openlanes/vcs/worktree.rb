# frozen_string_literal: true

require "fileutils"
require "shellwords"

module OpenLanes
  module Vcs
    # A git worktree per plan, so agents working on different plans cannot
    # collide at all.
    #
    # A lock coordinates a shared tree; a worktree removes the sharing. That
    # matters more than it sounds for an agent loop: two agents editing one
    # checkout produce no git conflict — same branch, same files — so the last
    # writer simply wins and the loser's work vanishes with nothing anywhere to
    # say it happened.
    #
    # The branch carries the plan number (`<user>/NNN.MM-slug`), which is not
    # decoration: it is the first thing `resync prs` reads when deciding which
    # plan a pull request implements. Naming branches this way means the number
    # carries itself from worktree creation through to a merged pull request with
    # nobody having to remember it.
    class Worktree
      # `bin/setup-worktree`, which copies in the ignored-but-required files a new
      # checkout does not get. Shelling out rather than reimplementing the rules
      # here keeps one answer to "what does a worktree need", and keeps that answer
      # usable from a shell on a machine that has never run `bundle install`.
      SEEDER = File.expand_path("../../../bin/setup-worktree", __dir__)

      # One plan's isolated checkout.
      #
      # @!attribute [r] ordinal
      #   @return [OpenLanes::Plans::Ordinal]
      # @!attribute [r] branch
      #   @return [String]
      # @!attribute [r] path
      #   @return [String] absolute
      # @!attribute [r] created
      #   @return [Boolean] false when an existing worktree was reused
      Checkout = Data.define(:ordinal, :branch, :path, :created) do
        # @return [Boolean] whether the agent left anything behind
        def dirty? = !`git -C #{path.shellescape} status --porcelain 2>/dev/null`.strip.empty?

        # @return [String] the plans directory inside this checkout
        def plans_dir = File.join(path, OpenLanes::PLANS_DIR)

        # @return [Boolean] whether this round made it, rather than reusing one
        def created? = created
      end

      # @param root [String] the main repository
      # @param dir [String, nil] where worktrees go; defaults to a sibling
      # @param user [String] branch namespace
      def initialize(root:, dir: nil, user: ENV["USER"] || "agent")
        @root = File.expand_path(root)
        @user = user
        @dir = File.expand_path(dir || default_dir)
      end

      # @return [String] the main repository
      attr_reader :root

      # @return [String] where worktrees are kept
      attr_reader :dir

      # @return [Boolean] whether root is a git repository at all
      def repository? = system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

      # Get, or create, the isolated checkout for one plan.
      #
      # The checkout is seeded before it is handed back, on both paths. `git
      # worktree add` brings every TRACKED file and nothing else, so an agent
      # given a bare one cannot run the suite it was told to keep green: a Rails
      # project dies on `MissingKeyError` because `config/credentials/*.key` is
      # gitignored. The agent then reports a broken checkout as a broken plan,
      # which is the worst failure this loop has, because the diagnosis points
      # at the code rather than at the tree.
      #
      # A reused worktree is seeded too. {#seed} only ever adds a missing file,
      # so running it again costs one fast subprocess and repairs the worktrees
      # that were created before any of this existed.
      #
      # @param feature [OpenLanes::Plans::Feature]
      # @return [OpenLanes::Vcs::Worktree::Checkout]
      # @raise [OpenLanes::Error] when git refuses
      def checkout_for(feature)
        branch = branch_for(feature)
        path = path_for(feature)

        if File.directory?(path)
          seed(path)
          return Checkout.new(ordinal: feature.ordinal, branch:, path:, created: false)
        end

        # git keeps a registration for a worktree whose directory was deleted by
        # hand, marks it `prunable`, and then refuses to create a new one at that
        # path. Anybody who has ever `rm -rf`d a worktree meets this, and the
        # error says only "already exists" about a directory that does not.
        forget_stale

        FileUtils.mkdir_p(dir)
        add(branch, path)
        seed(path)
        Checkout.new(ordinal: feature.ordinal, branch:, path:, created: true)
      end

      # Copy in the files git ignores and a new checkout therefore lacks: `.env`
      # and friends, and credential keys.
      #
      # Never fatal. A repository with no ignored files is perfectly normal, and
      # a plan is not worth abandoning over a seeding step, so this notes it and
      # carries on.
      #
      # The note goes to the progress log, never the terminal: this runs while
      # agents' spinner lines are live on STDERR, and a stray line lands in the
      # middle of them. The seeder's own output is silenced for the same reason. A suite that later dies on a missing key is explained
      # by the log line.
      #
      # @param path [String] the worktree to seed
      # @return [Boolean] whether the seeder ran and succeeded
      def seed(path)
        unless File.executable?(SEEDER)
          UI.log("worktree: #{SEEDER} is missing, so #{path} has no .env or credential keys")
          return false
        end

        return true if system(SEEDER, "--quiet", path, out: File::NULL, err: File::NULL)

        UI.log("worktree: could not seed #{path}; its suite may fail on a missing key")
        false
      end

      # @param feature [OpenLanes::Plans::Feature]
      # @return [String] e.g. "kig/002.00-tenancy-households"
      def branch_for(feature) = "#{@user}/#{feature.ordinal}-#{feature.slug}"

      # Every worktree this class manages, as git sees them.
      #
      # @return [Array<String>] absolute paths
      def list
        # Compare canonical paths. git reports resolved ones, and on macOS the
        # temp and home trees run through symlinks (/var -> /private/var), so a
        # raw string compare matches nothing and prune silently does nothing.
        mine = canonical(dir)

        `git -C #{root.shellescape} worktree list --porcelain 2>/dev/null`
          .lines(chomp: true)
          .filter_map { |l| l.delete_prefix("worktree ") if l.start_with?("worktree ") }
          .select { |p| canonical(p).start_with?(mine) }
      end

      # @param path [String]
      # @return [String] the symlink-resolved path, or the input when it is gone
      def canonical(path)
        File.realpath(path)
      rescue Errno::ENOENT
        path
      end

      # Remove worktrees the agents left untouched.
      #
      # An agent that ran and changed nothing has produced a checkout that is
      # pure cost: it looks like work in progress and is not. Dirty ones are
      # always kept — that is the output.
      #
      # @return [Array<String>] paths removed
      def prune
        list.select { |path| clean?(path) }.each { |path| remove(path) }
      end

      # Where one plan's checkout lives, whether or not it has been made.
      #
      # @param feature [OpenLanes::Plans::Feature]
      # @return [String]
      def path_for(feature) = File.join(dir, "#{feature.ordinal}-#{feature.slug}")

      # Throw away what has not been committed in one plan's checkout: every
      # change to a tracked file, and every untracked file that is not
      # ignored, so the seeded `.env` and keys stay. This is the reset behind
      # a person's discard (W9). Agents never commit, so everything a round
      # did is uncommitted, and the branch's own last commit is the base it
      # started from; going further back would drop work already published
      # behind an open pull request.
      #
      # It only ever runs inside a worktree this class manages. The main
      # checkout, or a directory git does not list as one of these
      # worktrees, is refused, because `reset --hard` there would take a
      # person's own work with it.
      #
      # @param feature [OpenLanes::Plans::Feature]
      # @return [Boolean] false when the plan has no checkout, so nothing to reset
      # @raise [OpenLanes::Error] when the path is not one of these worktrees,
      #   or git refuses
      def reset(feature)
        path = path_for(feature)
        return false unless File.directory?(path)

        mine = list.map { canonical(it) }
        unless mine.include?(canonical(path)) && canonical(path) != canonical(root)
          raise Error, "#{path} is not a worktree openlanes made, so it is not reset"
        end

        [%w[reset --hard --quiet], %w[clean -fd --quiet]].each do |args|
          next if system("git", "-C", path, *args, out: File::NULL, err: File::NULL)

          raise Error, "git #{args.first} failed in #{path}"
        end
        true
      end

      # @param path [String]
      # @return [void]
      def remove(path)
        system("git", "-C", root, "worktree", "remove", "--force", path, out: File::NULL, err: File::NULL)
      end

      private

      # Sibling of the repository, not inside it: a worktree under the repo shows
      # up in its own `git status` and in every glob anybody writes.
      #
      # @return [String]
      def default_dir = "#{@root}.worktrees"

      # Drop registrations whose directory is gone.
      #
      # @return [void]
      def forget_stale
        system("git", "-C", root, "worktree", "prune", out: File::NULL, err: File::NULL)
      end

      # @param path [String]
      # @return [Boolean]
      def clean?(path) = `git -C #{path.shellescape} status --porcelain 2>/dev/null`.strip.empty?

      # @param branch [String]
      # @param path [String]
      # @return [void]
      def add(branch, path)
        exists = system("git", "-C", root, "show-ref", "--verify", "--quiet", "refs/heads/#{branch}")
        args = exists ? ["worktree", "add", path, branch] : ["worktree", "add", "-b", branch, path]

        return if system("git", "-C", root, *args, out: File::NULL, err: File::NULL)

        raise Error, "could not create a worktree for #{branch} at #{path}"
      end
    end
  end
end
