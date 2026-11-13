# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "rbconfig"

module OpenLanes
  module Vcs
    # Gives a worktree its dependencies before an agent starts in it, off the
    # agent's clock.
    #
    # A fresh worktree has never run `bundle install` or `npm ci`, so the first
    # thing every agent did was spend minutes installing what the last plan's
    # worktree had already installed. Each kind installs into a directory of
    # the worktree's own, and the cache, one entry per lockfile digest, keeps a
    # clone of the result (`cp -cR`, an APFS clonefile, on macOS) for the next
    # worktree. The worktree never writes into the cache, so an agent that
    # edits an installed gem changes its own copy and no other plan's.
    #
    # Installing runs code the branch controls (a `Gemfile` is Ruby), in the
    # harness and outside the agent's boundary, so a kind is warmed only when
    # every file it reads matches the base branch, and npm runs with
    # `--ignore-scripts`. A kind whose target or `.bundle/config` git does not
    # ignore is skipped too, since `git add -A` would publish it.
    #
    # Never fatal, the same as seeding: a failure is reported in the {Result}
    # and the plan goes on, its agent left to install for itself.
    class Warmup
      # Where the shared installs live, one directory per kind and digest.
      DEFAULT_CACHE = File.join(Dir.home, ".cache", "openlanes", "deps")

      # The file a cache entry is complete without; an interrupted install
      # leaves an entry without it, which is then installed again.
      COMPLETE = ".complete"

      # The kinds warmed, in order.
      KINDS = [Kind::BUNDLER, Kind::NPM].freeze

      # The settings file a Bundler kind points at its target.
      BUNDLE_CONFIG = ".bundle/config"

      # What one warm-up did, kind by kind.
      #
      # @!attribute [r] installed
      #   @return [Array<Symbol>] kinds installed, and kept in the cache, by this call
      # @!attribute [r] shared
      #   @return [Array<Symbol>] kinds cloned from an entry already in the cache
      # @!attribute [r] skipped
      #   @return [Hash{Symbol => String}] kinds deliberately left alone, and why
      # @!attribute [r] failures
      #   @return [Hash{Symbol => String}] kinds that could not be warmed, and why
      Result = Data.define(:installed, :shared, :skipped, :failures) do
        def initialize(installed: [], shared: [], skipped: {}, failures: {}) = super

        # @return [Boolean] whether no kind failed
        def ok? = failures.empty?

        # @return [Boolean] whether the checkout had no lockfile at all
        def untouched? = installed.empty? && shared.empty? && skipped.empty? && failures.empty?
      end

      # The runner used when none is injected: run `argv` in `dir` with `env`,
      # silently, since agents' spinner lines are live on STDERR.
      DEFAULT_RUNNER = lambda do |argv, dir, env|
        system(env, *argv, chdir: dir, out: File::NULL, err: File::NULL)
      end

      # @param lockfile [String] path to a lockfile
      # @return [String] the cache key for its contents
      def self.digest(lockfile) = Digest::SHA256.file(lockfile).hexdigest[0, 16]

      # @param cache [String] where shared installs live
      # @param runner [#call] `(argv, dir, env) -> Boolean`; the suite injects
      #   one so it never runs bundler or npm for real
      # @param kinds [Array<Kind>]
      def initialize(cache: DEFAULT_CACHE, runner: DEFAULT_RUNNER, kinds: KINDS)
        @cache = File.expand_path(cache)
        @runner = runner
        @kinds = kinds
      end

      # @return [String]
      attr_reader :cache

      # @param path [String] the worktree to warm
      # @param base [String, nil] the ref whose dependency files are trusted;
      #   nil trusts the worktree's own
      # @return [Result]
      def call(path, base: nil)
        result = Result.new
        @kinds.each do |kind|
          next unless File.file?(File.join(path, kind.lockfile))

          why = refusal(kind, path, base)
          why ? result.skipped[kind.name] = why : warm(kind, path, result)
        rescue StandardError => e
          result.failures[kind.name] = e.message
        end
        result
      end

      # @param kind [Symbol]
      # @param lockfile [String]
      # @return [String] the cache entry for that kind and lockfile
      def entry_for(kind, lockfile) = File.join(cache, kind.to_s, self.class.digest(lockfile))

      private

      # @return [String, nil] why this kind must not be warmed here
      def refusal(kind, path, base)
        changed = base && kind.inputs.find { !same_as_base?(path, it, base) }
        return "#{changed} differs from #{base}" if changed

        # The trailing slash says the target is a directory, which a pattern
        # like `/node_modules/` only matches before it exists.
        unpublished = ["#{kind.target}/", *(BUNDLE_CONFIG if kind.bundler?)].find { !ignored?(path, it) }
        return "git does not ignore #{unpublished.chomp("/")}" if unpublished
        return "#{BUNDLE_CONFIG} is a symlink" if kind.bundler? && symlinked?(path, BUNDLE_CONFIG)
        return "already satisfied" if kind.check && @runner.call(kind.check, path, {})

        nil
      end

      # One kind, under a lock on its entry, so two worktrees warming at once
      # install it once between them rather than twice.
      def warm(kind, path, result)
        entry = entry_for(kind.name, File.join(path, kind.lockfile))
        target = File.join(path, kind.target)
        FileUtils.mkdir_p(File.dirname(entry))
        outcome = File.open("#{entry}.lock", File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          fill(kind, path, entry, target)
        end
        record(kind, path, outcome, result)
      end

      def record(kind, path, outcome, result)
        return result.failures[kind.name] = "#{kind.install.join(" ")} failed in #{path}" if outcome == :failed

        result.public_send(outcome) << kind.name
        point_bundler(path, File.join(path, kind.target)) if kind.bundler?
      end

      # @return [Symbol] :shared, :installed or :failed
      def fill(kind, path, entry, target)
        kept = File.join(entry, File.basename(kind.target))
        if complete?(entry)
          copy_on_write(kept, target) unless File.exist?(target)
          return :shared
        end
        # A node_modules already in the worktree is {Prewarm}'s clone from the
        # main checkout; `npm ci` would delete it and install again.
        return :shared if !kind.bundler? && File.exist?(target)
        return :failed unless @runner.call(kind.install, path, kind.env.call(target))

        keep(target, kept, entry)
        :installed
      end

      # Stores a fresh install as the entry for its digest.
      def keep(target, kept, entry)
        FileUtils.rm_rf(kept)
        FileUtils.mkdir_p(entry)
        copy_on_write(target, kept) if File.directory?(target)
        FileUtils.touch(File.join(entry, COMPLETE))
      end

      # Writes `BUNDLE_PATH` into the worktree's own `.bundle/config`, keeping
      # whatever else a person put there. {#refusal} has already checked that
      # git ignores the file and that it is no symlink.
      def point_bundler(path, target)
        config = File.join(path, BUNDLE_CONFIG)
        lines = File.file?(config) ? File.readlines(config, chomp: true).grep_v(/\A(---|BUNDLE_PATH:)/) : []
        FileUtils.mkdir_p(File.dirname(config))
        File.write(config, ["---", "BUNDLE_PATH: #{target.inspect}", *lines].join("\n") << "\n")
      end

      def complete?(entry) = File.file?(File.join(entry, COMPLETE))

      # Whether the worktree's copy of `file` is the one on `base`, compared
      # by blob id, so an uncommitted or untracked edit counts as a change.
      def same_as_base?(path, file, base)
        local = File.join(path, file)
        return !git?(path, "cat-file", "-e", "#{base}:#{file}") unless File.file?(local)

        theirs, ok = Open3.capture2("git", "-C", path, "rev-parse", "--verify", "--quiet", "#{base}:#{file}", err: File::NULL)
        ours, = Open3.capture2("git", "-C", path, "hash-object", "--", file, err: File::NULL)
        ok.success? && theirs.strip == ours.strip
      end

      def ignored?(path, file) = git?(path, "check-ignore", "--quiet", "--", file)

      def symlinked?(path, file)
        [File.dirname(file), file].any? { File.symlink?(File.join(path, it)) }
      end

      def git?(path, *) = system("git", "-C", path, *, out: File::NULL, err: File::NULL)

      # A copy-on-write clone where the filesystem offers one, a copy elsewhere.
      def copy_on_write(from, to)
        FileUtils.mkdir_p(File.dirname(to))
        return if RbConfig::CONFIG["host_os"].include?("darwin") &&
                  system("cp", "-cR", from, to, out: File::NULL, err: File::NULL)

        FileUtils.rm_rf(to)
        FileUtils.cp_r(from, to)
      end
    end
  end
end
