# frozen_string_literal: true

require "open3"

module OpenLanes
  module Setup
    # This machine, as openlanes needs it: `brew bundle` over the gem's
    # `Brewfile`, then the checks brew cannot settle. Every process and the
    # Redis ping go through injected seams, so the suite never runs brew.
    class Machine
      HOMEBREW_INSTALL =
        '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      CLAUDE_INSTALL = "curl -fsSL https://claude.ai/install.sh | bash"

      # A check runs `brew bundle check`, which would otherwise update
      # Homebrew first: a question about the machine must not take a minute
      # and change it.
      QUIET_BREW = { "HOMEBREW_NO_AUTO_UPDATE" => "1", "HOMEBREW_NO_ENV_HINTS" => "1" }.freeze

      # What one run did: what was missing before it, whether it ran
      # `brew bundle`, and the checks taken afterwards.
      Outcome = Data.define(:missing, :installed, :checks) do
        # @return [Boolean]
        def ok? = checks.all?(&:ok?)
      end

      # @param brewfile [String]
      # @param redis_url [String, nil] nil: W16's order, from the project when there is one
      # @param capture [#call] argv, env to [output, success]
      # @param install [#call] argv to success, its output left on the terminal
      # @param which [#call] a command name to whether it is on `PATH`
      # @param ping [#call] a Redis URL to whether it answered
      def initialize(brewfile: BREWFILE, redis_url: nil, capture: method(:capture),
        install: method(:install), which: method(:on_path?), ping: method(:ping?))
        @brewfile = brewfile
        @redis_url = redis_url
        @capture = capture
        @install = install
        @which = which
        @ping = ping
      end

      # Installs what the Brewfile lists and is missing, unless +dry_run+,
      # then checks the machine.
      #
      # @param dry_run [Boolean]
      # @return [Outcome]
      def call(dry_run: false)
        missing = brew? ? self.missing : []
        installed = !dry_run && brew? && !bundled? && @install.call(bundle_command)
        Outcome.new(missing:, installed: installed == true, checks:)
      end

      # Every check, read-only, in the order the report prints them.
      #
      # @return [Array<Check>]
      def checks = [brew_check, brewfile_check, claude_check, gh_check, redis_check]

      # @return [Boolean]
      def ready? = checks.all?(&:ok?)

      # What `brew bundle check` says the Brewfile lacks.
      #
      # @return [Array<String>] formula, cask and tap names
      def missing = needs(bundle_check.first)

      # @return [Array<String>] the command that installs the Brewfile
      def bundle_command = ["brew", "bundle", "--no-upgrade", "--file", @brewfile]

      # @return [String] the Redis the run would use
      def redis_url = @redis_url || Live.redis_url(config: config)

      private

      # @return [Boolean]
      def brew? = @which.call("brew")

      # `brew bundle check --verbose` names each lack as "Formula jq needs to be installed".
      #
      # @param output [String]
      # @return [Array<String>]
      def needs(output) = output.scan(/(?:Formula|Cask|Tap|Package) (\S+) needs/).flatten

      # @return [Boolean]
      def bundled? = bundle_check.last

      # @return [Array(String, Boolean)]
      def bundle_check
        @capture.call(["brew", "bundle", "check", "--verbose", "--no-upgrade", "--file", @brewfile], QUIET_BREW)
      end

      # @return [Check]
      def brew_check
        return Check.new(name: "brew", ok: true, detail: "Homebrew is installed", fix: nil) if brew?

        Check.new(name: "brew", ok: false, detail: "Homebrew is not on PATH", fix: HOMEBREW_INSTALL)
      end

      # @return [Check]
      def brewfile_check
        unless brew?
          return Check.new(name: "Brewfile", ok: false, detail: "needs Homebrew", fix: "install Homebrew, then: openlanes setup")
        end

        output, ok = bundle_check
        return Check.new(name: "Brewfile", ok: true, detail: "every tool in #{@brewfile} is installed", fix: nil) if ok

        names = needs(output)
        Check.new(name: "Brewfile",
          ok: false,
          detail: "missing: #{names.empty? ? "see brew bundle check" : names.join(", ")}",
          fix: bundle_command.join(" "))
      end

      # @return [Check]
      def claude_check
        return Check.new(name: "claude", ok: true, detail: "the claude CLI is on PATH", fix: nil) if @which.call("claude")

        Check.new(name: "claude", ok: false, detail: "the claude CLI is not on PATH", fix: CLAUDE_INSTALL)
      end

      # @return [Check]
      def gh_check
        unless @which.call("gh")
          return Check.new(name: "gh", ok: false, detail: "gh is not on PATH", fix: "brew install gh && gh auth login")
        end
        return Check.new(name: "gh", ok: true, detail: "gh auth status passes", fix: nil) if @capture.call(%w[gh auth status], {}).last

        Check.new(name: "gh", ok: false, detail: "gh is not logged in", fix: "gh auth login")
      end

      # @return [Check]
      def redis_check
        url = redis_url
        shown = Live.mask(url)
        return Check.new(name: "redis", ok: true, detail: "#{shown} answers PING", fix: nil) if @ping.call(url)

        local = url.match?(%r{\Aredis://(?:[^@/]*@)?(?:localhost|127\.0\.0\.1)(?::\d+)?(?:/|\z)})
        fix = local ? "brew services start redis" : "make #{shown} reachable, or set redis_url in .openlanes.yml"
        Check.new(name: "redis", ok: false, detail: "#{shown} does not answer", fix:)
      end

      # The project's settings when there is a project, else none: setup runs
      # from anywhere, and a broken `.openlanes.yml` is a question for the
      # commands that read it, not a reason the machine is not ready.
      #
      # @return [OpenLanes::Config]
      def config
        Config.current
      rescue OpenLanes::Error
        Config.new
      end

      # @return [Array(String, Boolean)]
      def capture(argv, env)
        output, status = Open3.capture2e(env, *argv)
        [output, status.success?]
      rescue SystemCallError
        ["", false]
      end

      # brew's progress belongs on STDERR: STDOUT carries the report.
      #
      # @return [Boolean]
      def install(argv) = system(*argv, out: $stderr, err: $stderr) == true

      # @return [Boolean]
      def on_path?(name) = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, name)) }

      # @return [Boolean]
      def ping?(url)
        Live.connect(url)
        true
      rescue Live::Unavailable, RedisClient::Error, ArgumentError
        false
      end
    end
  end
end
