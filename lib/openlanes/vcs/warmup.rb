# frozen_string_literal: true

require "digest"
require "fileutils"
require "rbconfig"

module OpenLanes
  module Vcs
    # Gives a worktree its dependencies before an agent starts in it, off the
    # agent's clock.
    #
    # A fresh worktree has never run `bundle install` or `npm ci`, so the first
    # thing every agent did was spend minutes installing what the last plan's
    # worktree had already installed. Dependencies are installed once per
    # lockfile digest into a cache outside the repository, and every worktree
    # whose lockfile has that digest shares the result: Bundler through a
    # worktree-local `.bundle/config` pointing `BUNDLE_PATH` at the cache, and
    # `node_modules` cloned from it (`cp -cR`, an APFS clonefile, on macOS).
    #
    # Never fatal, the same as seeding: a failure is reported in the {Result}
    # and the plan goes on, its agent left to install for itself.
    class Warmup
      # Where the shared installs live, one directory per kind and digest.
      DEFAULT_CACHE = File.join(Dir.home, ".cache", "openlanes", "deps")

      # The file a cache entry is complete without; an interrupted install
      # leaves an entry without it, which is then installed again.
      COMPLETE = ".complete"

      # Each kind of dependency: the lockfile that names it, and the command
      # that installs it into the directory it is run in.
      KINDS = {
        bundler: { lockfile: "Gemfile.lock", command: %w[bundle install --quiet] },
        npm:     { lockfile: "package-lock.json", command: %w[npm ci --silent --no-audit --no-fund] }
      }.freeze

      # What one warm-up did, kind by kind.
      #
      # @!attribute [r] installed
      #   @return [Array<Symbol>] kinds installed into the cache by this call
      # @!attribute [r] shared
      #   @return [Array<Symbol>] kinds taken from an entry already in the cache
      # @!attribute [r] failures
      #   @return [Hash{Symbol => String}] kinds that could not be warmed, and why
      Result = Data.define(:installed, :shared, :failures) do
        # @return [Boolean] whether every kind present was warmed
        def ok? = failures.empty?

        # @return [Boolean] whether the checkout had no lockfile at all
        def untouched? = installed.empty? && shared.empty? && failures.empty?
      end

      # The installer used when none is injected: run the kind's command in
      # `dir` with `env`, silently, since agents' spinner lines are live on
      # STDERR.
      DEFAULT_INSTALLER = lambda do |kind, dir, env|
        system(env, *KINDS.fetch(kind)[:command], chdir: dir, out: File::NULL, err: File::NULL)
      end

      # @param lockfile [String] path to a lockfile
      # @return [String] the cache key for its contents
      def self.digest(lockfile) = Digest::SHA256.file(lockfile).hexdigest[0, 16]

      # @param cache [String] where shared installs live
      # @param installer [#call] `(kind, dir, env) -> Boolean`; the suite
      #   injects one so it never runs bundler or npm for real
      def initialize(cache: DEFAULT_CACHE, installer: DEFAULT_INSTALLER)
        @cache = File.expand_path(cache)
        @installer = installer
      end

      # @return [String]
      attr_reader :cache

      # @param path [String] the worktree to warm
      # @return [Result]
      def call(path)
        result = { installed: [], shared: [], failures: {} }
        KINDS.each do |kind, spec|
          lockfile = File.join(path, spec[:lockfile])
          next unless File.file?(lockfile)

          warm(kind, path, entry_for(kind, lockfile), result)
        rescue SystemCallError, IOError => e
          result[:failures][kind] = e.message
        end
        Result.new(**result)
      end

      # @param kind [Symbol]
      # @param lockfile [String]
      # @return [String] the cache entry for that kind and lockfile
      def entry_for(kind, lockfile) = File.join(cache, kind.to_s, self.class.digest(lockfile))

      private

      # One kind, under a lock on its entry, so two worktrees warming at once
      # install it once between them rather than twice into one directory.
      def warm(kind, path, entry, result)
        FileUtils.mkdir_p(File.dirname(entry))
        File.open("#{entry}.lock", File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          send(kind, path, entry, result)
        end
      end

      # Bundler installs straight into the entry, so the worktree only needs
      # to be told where it is.
      def bundler(path, entry, result)
        point_bundler(path, entry)
        if complete?(entry)
          result[:shared] << :bundler
        elsif @installer.call(:bundler, path, { "BUNDLE_PATH" => entry })
          complete!(entry)
          result[:installed] << :bundler
        else
          result[:failures][:bundler] = "bundle install failed in #{path}"
        end
      end

      # npm has no path setting, so it installs in the worktree and the entry
      # keeps a clone of the result for the next worktree. A `node_modules`
      # already in the worktree is {Prewarm}'s clone from the main checkout;
      # `npm ci` would delete it and install again, so it is left as it is.
      def npm(path, entry, result)
        target = File.join(path, "node_modules")
        if complete?(entry) || File.exist?(target)
          clone(File.join(entry, "node_modules"), target) unless File.exist?(target)
          result[:shared] << :npm
        elsif @installer.call(:npm, path, {})
          keep(target, entry)
          result[:installed] << :npm
        else
          result[:failures][:npm] = "npm ci failed in #{path}"
        end
      end

      # Stores a fresh install's node_modules as the entry for its digest.
      def keep(target, entry)
        FileUtils.rm_rf(File.join(entry, "node_modules"))
        FileUtils.mkdir_p(entry)
        clone(target, File.join(entry, "node_modules")) if File.directory?(target)
        complete!(entry)
      end

      # Writes `BUNDLE_PATH` into the worktree's own `.bundle/config`, keeping
      # whatever else a person put there.
      def point_bundler(path, entry)
        config = File.join(path, ".bundle", "config")
        lines = File.file?(config) ? File.readlines(config, chomp: true).grep_v(/\A(---|BUNDLE_PATH:)/) : []
        FileUtils.mkdir_p(File.dirname(config))
        File.write(config, ["---", "BUNDLE_PATH: #{entry.inspect}", *lines].join("\n") << "\n")
      end

      def complete?(entry) = File.file?(File.join(entry, COMPLETE))

      def complete!(entry)
        FileUtils.mkdir_p(entry)
        FileUtils.touch(File.join(entry, COMPLETE))
      end

      # A copy-on-write clone where the filesystem offers one, a copy elsewhere.
      def clone(from, to)
        return if RbConfig::CONFIG["host_os"].include?("darwin") &&
                  system("cp", "-cR", from, to, out: File::NULL, err: File::NULL)

        FileUtils.rm_rf(to)
        FileUtils.cp_r(from, to)
      end
    end
  end
end
