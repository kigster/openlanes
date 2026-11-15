# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module OpenLanes
  module Supervision
    # `npm run build` in the gem's `web/`, for `/restart-web` (plan 069.00).
    # The {Supervisor} ticks every {Supervisor::TICK} seconds and must not
    # block on a build, so {#start} spawns it and {#poll} asks after it.
    #
    # Only OpenLanes working on itself builds: the project root holds a
    # `justfile` and `.openlanes/config.yml` says `project: openlanes`.
    # Anywhere else the page is the one the gem shipped, a build would
    # rewrite the installed gem, and the restart goes on without one
    # ({Outcome#skipped?}), saying nothing.
    #
    # A build that cannot run or fails leaves `web/dist` as it was (D3):
    # a {PageBackup} keeps the old page and puts it back on any outcome
    # but `ok`. The build's output goes to a log in a private directory,
    # removed once the outcome is settled.
    class WebRebuild
      # Seconds a build may run before it is killed and counted a failure.
      TIMEOUT = 300

      # Lines of the build's output kept for the reply.
      TAIL = 15

      # What one build came to.
      #
      # @!attribute [r] status
      #   @return [String] ok, skipped, no_npm, no_sources, failed or timeout
      # @!attribute [r] message
      #   @return [String] a sentence a person reads in the copilot
      Outcome = Data.define(:status, :message) do
        # @return [Boolean]
        def ok? = status == "ok"

        # @return [Boolean] whether no build was called for, so there is nothing to tell
        def skipped? = status == "skipped"
      end

      # Whether `npm` is on PATH.
      NPM_ON_PATH = lambda do
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, "npm")) }
      end

      # The `project:` that marks OpenLanes working on itself, compared
      # without case, as the page's header does.
      OWN_PROJECT = "openlanes"

      # The file whose `web-build` recipe this build is.
      JUSTFILE = "justfile"

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
      # A `web/` that cannot be read or written (a gem installed by another
      # user) raises from the backup or the spawn. That is a build failure
      # to report, never an error to raise: nothing between here and
      # {Supervisor#tick} rescues, so it would end `openlanes start`, the
      # engine with it (F1).
      #
      # @return [self]
      def start
        return self if @pid || @outcome || unbuildable

        spawn_build
        self
      rescue SystemCallError => e
        # Nothing was built, so there is nothing to put back.
        @backup&.discard
        settle("failed", "the build could not start (#{e.message}), so the old page stays")
        self
      end

      # Never blocks, and never raises a {SystemCallError} (F1).
      #
      # @return [Outcome, nil] nil while the build runs
      def poll
        return @outcome if @outcome

        status = @host.waiter.call(@pid)
        return finished(status) if status

        stop_late_build
        nil
      rescue SystemCallError => e
        settle("failed", "the build's outcome could not be read (#{e.message}), so the old page stays")
      end

      private

      # Settles at once when there is nothing to build with.
      #
      # @return [Outcome, nil]
      def unbuildable
        return settle("skipped", "the page was not rebuilt: this project is not OpenLanes itself") unless own_project?
        return settle("no_sources", "the page was not rebuilt: #{@web}/package.json is missing") unless File.exist?(File.join(@web, "package.json"))

        settle("no_npm", "the page was not rebuilt: npm is not on PATH") unless @npm.call
      end

      # Asked of the project the supervisor runs in, which `openlanes start`
      # has already moved to, through the same {Config.current} every
      # command reads. A config that cannot be read is not ours to build
      # for, and must not raise: this runs on the supervisor's tick (F1).
      #
      # @return [Boolean]
      def own_project?
        root = Project.root || Dir.pwd
        File.file?(File.join(root, JUSTFILE)) && Config.current.project.to_s.casecmp?(OWN_PROJECT)
      rescue OpenLanes::Error, SystemCallError
        false
      end

      # @return [void]
      def spawn_build
        @backup = PageBackup.new(File.join(@web, "dist")).keep
        # A private directory (mode 0700), never a predictable name in a
        # shared tmp: `spawn(out:)` follows a symlink planted there (F101).
        @workdir = Dir.mktmpdir("openlanes-web-build")
        @log = File.join(@workdir, "build.log")
        @started = @host.clock.monotonic
        @pid = @host.spawner.spawn({}, "npm", "run", "build", chdir: @web, pgroup: true, in: File::NULL, out: @log, err: %i[child out])
      end

      # @param status [Process::Status, Symbol]
      # @return [Outcome]
      def finished(status)
        return settle("timeout", "the build ran past #{@timeout} seconds and was stopped, so the old page stays") if @killed
        return settle("ok", "the page was rebuilt") if status.respond_to?(:exitstatus) && status.exitstatus&.zero?

        settle("failed", "the build failed (#{Host.describe(status)}), so the old page stays#{tail}")
      end

      # Kills a build past its time, once. It settles on a later {#poll},
      # when the waiter has reaped it: a single non-blocking wait straight
      # after the KILL finds nothing ended yet, and with nobody asking
      # after the pid again the build would stay a zombie (F2).
      #
      # @return [void]
      def stop_late_build
        return if @killed || @host.clock.monotonic - @started <= @timeout

        @killed = true
        @host.signaller.call("KILL", -@pid)
      end

      # Never raises: an old page that cannot be put back is said in the
      # outcome, since this runs on the supervisor's tick (F1).
      #
      # @param status [String]
      # @param message [String]
      # @return [Outcome]
      def settle(status, message)
        @outcome = Outcome.new(status:, message:)
        @outcome.ok? ? @backup&.discard : @backup&.restore
        @outcome
      rescue SystemCallError => e
        @outcome = Outcome.new(status: "failed", message: "#{message}; the old page could not be put back (#{e.message})")
      ensure
        FileUtils.rm_rf(@workdir) if @workdir
      end

      # Read before {#settle} removes the log.
      #
      # @return [String] the end of the build's output, or nothing
      def tail
        lines = @log && File.exist?(@log) ? File.readlines(@log).last(TAIL).join.strip : ""
        lines.empty? ? "" : ":\n#{lines}"
      end
    end
  end
end
