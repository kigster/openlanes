# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module OpenLanes
  module Supervision
    # `npm run build` in the gem's `web/`, for `/restart-web` (plan 069.00).
    # The {Supervisor} ticks every {Supervisor::TICK} seconds and must not
    # block on a build, so {#start} spawns it and {#poll} asks after it.
    #
    # A build that cannot run or fails leaves `web/dist` as it was (D3):
    # `vite build` empties its out dir before it writes, so the old page is
    # copied aside first and put back on any outcome but `ok`.
    class WebRebuild
      # Seconds a build may run before it is killed and counted a failure.
      TIMEOUT = 300

      # Lines of the build's output kept for the reply.
      TAIL = 15

      # What one build came to.
      #
      # @!attribute [r] status
      #   @return [String] ok, no_npm, no_sources, failed or timeout
      # @!attribute [r] message
      #   @return [String] a sentence a person reads in the copilot
      Outcome = Data.define(:status, :message) do
        # @return [Boolean]
        def ok? = status == "ok"
      end

      # Whether `npm` is on PATH.
      NPM_ON_PATH = lambda do
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, "npm")) }
      end

      # @param root [String] the gem's root, whose `web/` holds the page sources
      # @param host [OpenLanes::Supervision::Host]
      # @param npm [#call] whether `npm` can be run
      # @param timeout [Numeric]
      def initialize(root: Web::GEM_ROOT, host: Host::SYSTEM, npm: NPM_ON_PATH, timeout: TIMEOUT)
        @web = File.join(root, "web")
        @host = host
        @npm = npm
        @timeout = timeout
        @outcome = nil
      end

      # Spawns the build, or settles at once when it cannot run. Asked
      # again, it does nothing, so a tick may call it every time.
      #
      # @return [self]
      def start
        return self if @pid || @outcome || unbuildable

        keep_old_page
        @log = File.join(Dir.tmpdir, "openlanes-web-build-#{::Process.pid}.log")
        @started = @host.clock.monotonic
        @pid = @host.spawner.spawn({}, "npm", "run", "build", chdir: @web, pgroup: true, in: File::NULL, out: @log, err: %i[child out])
        self
      end

      # Never blocks.
      #
      # @return [Outcome, nil] nil while the build runs
      def poll
        return @outcome if @outcome

        status = @host.waiter.call(@pid)
        return finished(status) if status
        return timed_out if @host.clock.monotonic - @started > @timeout

        nil
      end

      private

      # Settles at once when there is nothing to build with.
      #
      # @return [Outcome, nil]
      def unbuildable
        return settle("no_sources", "the page was not rebuilt: #{@web}/package.json is missing") unless File.exist?(File.join(@web, "package.json"))

        settle("no_npm", "the page was not rebuilt: npm is not on PATH") unless @npm.call
      end

      # @param status [Process::Status, Symbol]
      # @return [Outcome]
      def finished(status)
        return settle("ok", "the page was rebuilt") if status.respond_to?(:exitstatus) && status.exitstatus&.zero?

        settle("failed", "the build failed (#{Host.describe(status)}), so the old page stays#{tail}")
      end

      # @return [Outcome]
      def timed_out
        @host.signaller.call("KILL", -@pid)
        @host.waiter.call(@pid)
        settle("timeout", "the build ran past #{@timeout} seconds and was stopped, so the old page stays")
      end

      # @param status [String]
      # @param message [String]
      # @return [Outcome]
      def settle(status, message)
        @outcome = Outcome.new(status:, message:)
        @outcome.ok? ? discard_old_page : restore_old_page
        @outcome
      end

      # @return [void]
      def keep_old_page
        dist = File.join(@web, "dist")
        return unless File.directory?(dist)

        @kept = Dir.mktmpdir("openlanes-web-dist")
        FileUtils.cp_r(File.join(dist, "."), @kept)
      end

      # @return [void]
      def restore_old_page
        return unless @kept

        dist = File.join(@web, "dist")
        FileUtils.rm_rf(dist)
        FileUtils.mkdir_p(dist)
        FileUtils.cp_r(File.join(@kept, "."), dist)
        discard_old_page
      end

      # @return [void]
      def discard_old_page
        FileUtils.rm_rf(@kept) if @kept
        @kept = nil
      end

      # @return [String] the end of the build's output, or nothing
      def tail
        lines = File.exist?(@log.to_s) ? File.readlines(@log).last(TAIL).join.strip : ""
        lines.empty? ? "" : ":\n#{lines}"
      end
    end
  end
end
