# frozen_string_literal: true

require "open3"

module OpenLanes
  module Lifecycle
    # Who may hand out a plan number, and which numbers are already gone.
    #
    # A number used to be the highest one in the `.plans` of whichever
    # checkout ran `create`. Two checkouts on two branches each saw only
    # their own folders and minted the same number: `main` stopped at 023
    # while 024 to 035 lived on an unmerged branch, so `create` on `main`
    # handed out 024 a second time, and the two plans collided the moment
    # both branches reached `main`. So, decided 2026-10-17:
    #
    # - plans are minted only in the primary checkout, never in a linked
    #   worktree, so there is one place numbers come from;
    # - a number counts as taken when it is in that checkout's `.plans`
    #   (archive and friends included, N3) or in `.plans` on any local
    #   branch or `origin/*` remote-tracking branch, read with `ls-tree`
    #   and no fetch;
    # - the numbers are read and the folder made under an exclusive lock in
    #   the shared git directory, so two `create`s at once cannot both take
    #   the number they both just saw was free.
    #
    # Decided 2026-10-20, on top of that: the primary checkout must also be on
    # the default branch (origin's HEAD, else `main`). A plan minted on a
    # feature branch there is a plan `main` does not know about until that
    # branch merges, which is the same split by another road. The rule covers
    # new folders, their opening `spec.md` and `depends_on:`; every other file
    # in a plan folder is still written from worktrees, as agents do.
    #
    # Outside a git repository there are no branches and no worktrees, and
    # the checkout's own `.plans` is the whole truth, as before.
    #
    # {Plans::Ordinal} stays arithmetic over the list this returns; the git
    # lives here and nowhere else.
    class Allocator
      # The lock file, in `git rev-parse --git-common-dir`: the one directory
      # every worktree of a repository shares.
      LOCK_FILE = "openlanes-ordinal.lock"

      # Where branches that may carry plans live. Other remotes are someone
      # else's forks; their numbers were never handed out here.
      REFS = %w[refs/heads refs/remotes/origin].freeze

      # The branch plans are minted on when origin names no default.
      DEFAULT_BRANCH = "main"

      # Raised when a plan would be minted in a linked worktree, or in the
      # primary checkout off its default branch.
      class Refused < OpenLanes::Error; end

      # The repository around a `.plans` directory, as git reports it.
      #
      # @!attribute [r] git_dir
      #   @return [String] this checkout's git directory, absolute
      # @!attribute [r] common_dir
      #   @return [String] the directory every worktree shares, absolute
      # @!attribute [r] toplevel
      #   @return [String] this checkout's root
      # @!attribute [r] plans
      #   @return [String] the `.plans` directory, relative to +toplevel+
      # @!attribute [r] branch
      #   @return [String, nil] the checked-out branch; nil on a detached HEAD
      # @!attribute [r] default_branch
      #   @return [String] origin's HEAD, else {DEFAULT_BRANCH}
      Repository = Data.define(:git_dir, :common_dir, :toplevel, :plans, :branch, :default_branch) do
        # A linked worktree has a git directory of its own under the common
        # one; the primary checkout's git directory is the common one.
        #
        # @return [Boolean]
        def worktree? = git_dir != common_dir

        # @return [String] the primary checkout, which owns the common directory
        def primary = File.basename(common_dir) == ".git" ? File.dirname(common_dir) : common_dir

        # @return [String]
        def lock_path = File.join(common_dir, LOCK_FILE)

        # @return [Boolean]
        def on_default_branch? = branch == default_branch
      end

      # @param dir [String] the `.plans` directory; need not exist yet
      def initialize(dir:)
        @dir = File.expand_path(dir)
      end

      # @return [String]
      attr_reader :dir

      # @return [Repository, nil] nil outside a git repository
      def repository = defined?(@repository) ? @repository : (@repository = discover)

      # @return [String, nil] why a plan may not be minted here, or nil when it may
      def refusal
        repo = repository or return
        if repo.worktree?
          return "plans are created only in the primary checkout, #{repo.primary}; this is a worktree of it"
        end
        return if repo.on_default_branch?

        "plans are created only on #{repo.default_branch} in the primary checkout; " \
          "#{repo.primary} is on #{repo.branch || "a detached HEAD"}"
      end

      # @return [void]
      # @raise [Refused] in a linked worktree, or off the default branch
      def refuse!
        message = refusal
        raise Refused, message if message
      end

      # Run the block holding the allocation lock: read {#taken} and create
      # the folder inside it, or another `create` can read the same numbers
      # in between.
      #
      # The lock is `flock`, so it dies with the process: a `create` killed
      # mid-way leaves nothing for anyone to break.
      #
      # @yieldreturn [Object]
      # @return [Object] the block's value
      # @raise [Refused] in a linked worktree, or off the default branch
      def hold
        refuse!
        repo = repository or return yield

        File.open(repo.lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      end

      # Every number a new plan must stay clear of.
      #
      # @return [Array<OpenLanes::Plans::Ordinal>] unique, unordered
      def taken
        local = Plans::Tree.new(dir:).taken
        repo = repository or return local

        (local + branches(repo).flat_map { OpenLanes.plans_at(repo.toplevel, it, plans: repo.plans) }).uniq
      end

      private

      # Branches that point at one commit hold one set of plans, so each
      # commit is read once: a branch and its `origin/` twin cost one `ls-tree`.
      #
      # @param repo [Repository]
      # @return [Array<String>] commit names
      def branches(repo)
        out = git(repo.toplevel, "for-each-ref", "--format=%(objectname) %(refname)", *REFS) or return []

        out.lines.filter_map { |line|
          sha, ref = line.split
          sha unless ref.to_s.end_with?("/HEAD")
        }.uniq
      end

      # @return [Repository, nil]
      def discover
        base = dir
        base = File.dirname(base) until File.directory?(base)
        out = git(base,
          "rev-parse",
          "--path-format=absolute",
          "--git-dir",
          "--git-common-dir",
          "--show-toplevel") or return nil
        git_dir, common_dir, toplevel = out.lines.map(&:chomp)
        return nil if toplevel.to_s.empty?

        Repository.new(git_dir:,
          common_dir:,
          toplevel:,
          plans: relative_plans(base, toplevel),
          branch: git(toplevel, "symbolic-ref", "--short", "-q", "HEAD")&.chomp,
          default_branch: default_branch(toplevel))
      end

      # origin's HEAD names the default branch where a clone recorded it; a
      # repository with no origin, or one never told, falls back to `main`.
      #
      # @param toplevel [String]
      # @return [String]
      def default_branch(toplevel)
        head = git(toplevel, "symbolic-ref", "--short", "-q", "refs/remotes/origin/HEAD")&.chomp
        head.to_s.empty? ? DEFAULT_BRANCH : head.delete_prefix("origin/")
      end

      # git answers with resolved paths (`/private/var` on macOS) while +dir+
      # may name the same place through a symlink (`/var`), so both sides are
      # resolved before one is taken from the other.
      #
      # @param base [String] the nearest existing ancestor of +dir+, or +dir+
      # @param toplevel [String]
      # @return [String]
      def relative_plans(base, toplevel)
        tail = dir.delete_prefix(base).delete_prefix("/")
        inside = File.realpath(base).delete_prefix(File.realpath(toplevel)).delete_prefix("/")
        File.join(*[inside, tail].reject(&:empty?)).then { it.empty? ? "." : it }
      end

      # @param dir [String]
      # @param args [Array<String>]
      # @return [String, nil] stdout, or nil when git failed or is not here
      def git(dir, *)
        out, status = Open3.capture2("git", "-C", dir, *, err: File::NULL)
        status.success? ? out : nil
      rescue SystemCallError
        nil
      end
    end
  end
end
