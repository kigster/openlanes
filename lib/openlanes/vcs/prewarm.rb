# frozen_string_literal: true

require "fileutils"
require "rbconfig"

module OpenLanes
  module Vcs
    # Gives a new worktree the main checkout's installed JavaScript
    # dependencies, so a plan's agent does not open with an `npm ci`.
    #
    # `git worktree add` brings tracked files only, and `node_modules` is
    # never one of them. Ruby does not have this problem (gems live in the
    # Ruby, shared by every checkout), but every worktree of a project with a
    # `package.json` used to pay for a full install before its suite could
    # run, once per plan.
    #
    # The copy is a copy-on-write clone where the filesystem has one (APFS,
    # btrfs, XFS): no data is copied until one side writes, so it takes about
    # a second and costs no disk. It is never a symlink. A symlink is faster
    # still, but then one worktree's `npm install` rewrites the tree every
    # other worktree and the main checkout are running from.
    #
    # A clone is only right when both sides would install the same thing, so
    # a lockfile that reads differently in the worktree is left alone, and
    # the agent installs as it always did.
    class Prewarm
      # The lockfiles whose sibling `node_modules` is cloned. `bun.lockb` is
      # the binary one bun wrote before 1.2.
      LOCKFILES = %w[package-lock.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb].freeze

      # What gets cloned, beside each lockfile.
      MODULES = "node_modules"

      # What happened beside one lockfile.
      #
      # @!attribute [r] lockfile
      #   @return [String] relative to the checkout, e.g. "web/package-lock.json"
      # @!attribute [r] kind
      #   @return [Symbol] :cloned, :skipped or :failed
      # @!attribute [r] reason
      #   @return [String, nil] why it was skipped or failed
      Outcome = Data.define(:lockfile, :kind, :reason) do
        # @return [Boolean]
        def cloned? = kind == :cloned

        # @return [Boolean]
        def failed? = kind == :failed

        # @return [String] the directory that was, or would have been, cloned
        def modules = File.join(File.dirname(lockfile), MODULES).delete_prefix("./")

        # @return [String] one line for the progress log
        def to_s = cloned? ? "#{modules} cloned from the main checkout" : "#{modules} not cloned: #{reason}"
      end

      class << self
        # The `cp` that clones a tree on this machine.
        #
        # Both flags fall back to an ordinary copy on a filesystem that
        # cannot clone, and that is wanted: copying an installed tree off the
        # local disk is still several times faster than `npm ci`, which
        # unpacks every tarball again and may reach the network, and the
        # result is the same tree. Anywhere else gets the ordinary copy
        # outright. `-a` keeps the `.bin` symlinks as symlinks and the
        # executable bits on what they point at.
        #
        # @param host_os [String]
        # @return [Array<String>] argv, without source and destination
        def copy_command(host_os = RbConfig::CONFIG["host_os"])
          case host_os
          when /darwin/ then %w[cp -c -a]
          when /linux/ then %w[cp --reflink=auto -a]
          else %w[cp -a]
          end
        end
      end

      # @param root [String] the main checkout, whose `node_modules` are cloned
      # @param command [Array<String>] the copy, without source and destination
      def initialize(root:, command: self.class.copy_command)
        @root = File.expand_path(root)
        @command = command
      end

      # Clone every `node_modules` the worktree is missing and may share.
      #
      # Never raises and never fails the checkout: a worktree without its
      # dependencies is exactly what every worktree was before this existed.
      # Each outcome that is not a silent skip goes to the progress log,
      # never the terminal, for the reason {Worktree#seed} gives.
      #
      # @param path [String] the worktree
      # @return [Array<OpenLanes::Vcs::Prewarm::Outcome>] one per lockfile
      def call(path)
        path = File.expand_path(path)
        return [] if path == @root

        lockfiles(path).map { |lockfile| warm(path, lockfile).tap { report(it, path) } }
      rescue SystemCallError => e
        UI.log("worktree: could not pre-warm #{path}: #{e.message}", level: :warn)
        []
      end

      private

      # The lockfiles git tracks in the worktree. Asking git, not the disk,
      # keeps this out of `node_modules` itself, where every dependency that
      # was published with its own lockfile would otherwise be found.
      #
      # @param path [String]
      # @return [Array<String>] relative paths
      def lockfiles(path)
        specs = LOCKFILES.flat_map { [it, ":(glob)**/#{it}"] }
        out = IO.popen(["git", "-C", path, "ls-files", "-z", "--", *specs], err: File::NULL, &:read)
        out.split("\0").reject { it.split("/").include?(MODULES) }
      end

      # @param path [String] the worktree
      # @param lockfile [String] relative
      # @return [OpenLanes::Vcs::Prewarm::Outcome]
      def warm(path, lockfile)
        relative = File.join(File.dirname(lockfile), MODULES)
        source = File.join(@root, relative)
        target = File.join(path, relative)
        reason = refusal(path, lockfile, source, target)
        return Outcome.new(lockfile:, kind: :skipped, reason:) if reason

        clone(source, target) ? Outcome.new(lockfile:, kind: :cloned, reason: nil) : Outcome.new(lockfile:, kind: :failed, reason: "#{@command.first} failed")
      end

      # The first reason not to clone, or nil.
      #
      # The ignore check is what keeps a clone from being mistaken for the
      # agent's work: an unignored `node_modules` makes the checkout dirty,
      # so it would never be pruned and its files would reach `git add -A`.
      #
      # @return [String, nil]
      def refusal(path, lockfile, source, target)
        return "it is already there" if File.exist?(target) || File.symlink?(target)
        return "the main checkout has none" unless File.directory?(source) && !File.symlink?(source)
        return "#{lockfile} differs from the main checkout's" unless same?(File.join(@root, lockfile), File.join(path, lockfile))

        "git does not ignore it here" unless ignored?(path, File.join(File.dirname(lockfile), MODULES))
      end

      # @return [Boolean] both exist and read the same
      def same?(ours, theirs) = File.file?(ours) && File.file?(theirs) && FileUtils.identical?(ours, theirs)

      # @return [Boolean]
      def ignored?(path, relative)
        system("git", "-C", path, "check-ignore", "--quiet", relative, out: File::NULL, err: File::NULL)
      end

      # Clone under another name, then rename. A copy that dies halfway
      # would otherwise leave a `node_modules` that exists, so is never
      # cloned again, and is missing half its packages: a suite failing on a
      # module that is plainly in `package.json`.
      #
      # @return [Boolean]
      def clone(source, target)
        staging = "#{target}.prewarm-#{Process.pid}"
        ok = system(*@command, source, staging, out: File::NULL, err: File::NULL)
        File.rename(staging, target) if ok
        ok ? true : false
      ensure
        FileUtils.rm_rf(staging) if staging
      end

      # Skips are the common case on a reused worktree, and say nothing.
      #
      # @return [void]
      def report(outcome, path)
        return if outcome.kind == :skipped && outcome.reason == "it is already there"

        UI.log("worktree: #{File.basename(path)}: #{outcome}", level: outcome.failed? ? :warn : :info)
      end
    end
  end
end
