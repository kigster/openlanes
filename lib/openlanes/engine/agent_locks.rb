# frozen_string_literal: true

require "json"
require "socket"
require "tty/command"

module OpenLanes
  module Engine
    # The plans an agent outside openlanes is working on, as `alock` (the
    # agent-lock gem) records them, and the engine's own claim in the same
    # register (decision W31).
    #
    # The Redis claim (W26) keeps engines apart and the lock file keeps two
    # runs on one machine apart, but an agent a person started by hand reads
    # neither. It does read alock: every agent here claims what it is about
    # to write. So the engine stays out of a plan whose folder, or whose
    # worktree, somebody else holds, and holds the folder itself while its
    # agents are in it, so that agent sees the engine too. With alock on
    # Redis this reaches across machines as well.
    #
    # `alock acquire` is the atomic step: it refuses (exit 1) when anybody
    # holds an overlapping scope, so two contenders cannot both win. The
    # listing only keeps the engine from asking, tick after tick, for plans
    # it would be refused.
    #
    # alock is a command, not a library: its holder is the process that runs
    # it, skipping shells, which is the engine itself, so a lock ends with
    # the engine that took it. A machine without alock has no agent using it
    # either, and the engine carries on without it, said once.
    class AgentLocks
      # How long one `alock list` answers for. The dispatcher asks on every
      # one-second tick, and each answer starts a Ruby process.
      FRESH = 5

      # One lock, as `alock list --json` reports it.
      #
      # @!attribute [r] agent
      #   @return [String] the holder's agent id
      # @!attribute [r] scope
      #   @return [String] relative to {#tree}, e.g. `.plans/003.00━━🟡━━❯x/**`
      # @!attribute [r] tree
      #   @return [String] the checkout the lock was taken in
      # @!attribute [r] intent
      #   @return [String, nil]
      Held = Data.define(:agent, :scope, :tree, :intent) do
        # @return [String] the scope's literal part: `**` is "", `a/b/**` is "a/b"
        def fixed = scope.split("/").take_while { !it.match?(/[*?\[{]/) }.join("/")

        # @return [String] who holds it and why, for the log
        def to_s = "#{agent} (#{intent || "no intent given"})"
      end

      # @param root [String] the repository whose plans are locked
      # @param id [String] the agent id the engine's own locks carry
      # @param own [Array<String>] the engine's agents, who claim with
      #   `AGENT_ID=<name>` or `<name>-<suffix>` as their prompt tells them to
      # @param command [TTY::Command]
      # @param clock [#call] monotonic seconds
      def initialize(root:, id: "openlanes@#{Socket.gethostname}:#{Process.pid}", own: [],
        command: TTY::Command.new(printer: :null), clock: -> { UI.monotonic })
        @root = File.realpath(root)
        @id = id
        @own = own
        @failing = nil
        @command = command
        @clock = clock
        @mutex = Mutex.new
        @snapshot = nil
        @taken_at = nil
        @off = false
      end

      # @return [String]
      attr_reader :id

      # Somebody else's live lock that overlaps the plan's folder, or any
      # lock taken inside its worktree. The engine's own agents are not
      # somebody else: they claim each file before writing it, so counting
      # them would keep a pair's partner out of the plan while the first one
      # works in it.
      #
      # @param dir [String] the plan folder
      # @param checkout [String, nil] the plan's worktree, when the run isolates
      # @return [Held, nil]
      def held_elsewhere(dir, checkout: nil)
        folder = real(dir)
        work = checkout && real(checkout)
        held.find do |lock|
          next false if ours?(lock.agent)

          tree = real(lock.tree)
          (work && tree == work) || (inside?(folder, tree) && overlap?(relative(folder, tree), lock.fixed))
        end
      end

      # Anybody's live lock taken inside one checkout, the engine's own
      # included: a worktree with a lock in it is in use, whoever holds it.
      #
      # @param checkout [String]
      # @return [Held, nil]
      def held_in(checkout)
        work = real(checkout)
        held.find { real(it.tree) == work }
      end

      # Claim the plan's folder. False when somebody holds it, in which case
      # the plan is left alone; true when alock is not installed.
      #
      # @param dir [String] the plan folder
      # @param intent [String] what the engine is about to do there
      # @return [Boolean]
      def acquire(dir, intent)
        run("acquire", scope(dir), intent, dir: File.dirname(dir))
      end

      # @param dir [String] the plan folder, as it was named when acquired
      # @return [void]
      def release(dir)
        run("release", scope(dir), dir: File.dirname(dir))
      end

      private

      # @param agent [String] a lock's holder
      # @return [Boolean] the engine itself, one of its agents, or a sub-agent of one
      def ours?(agent) = agent == @id || @own.any? { agent == it || agent.start_with?("#{it}-") }

      # @return [Array<Held>] every active lock, at most {FRESH} seconds old
      def held
        @mutex.synchronize do
          return [] if @off
          return @snapshot if @snapshot && @clock.call - @taken_at < FRESH

          @snapshot = list
          @taken_at = @clock.call
          @snapshot
        end
      end

      # @return [Array<Held>]
      def list
        out = @command.run("alock", "list", "--json", "--dir", @root).out
        listed = JSON.parse(out).filter_map do |lock|
          next unless lock["status"] == "active"

          Held.new(agent: lock["agent_id"].to_s, scope: lock["scope"].to_s, tree: lock["tree"].to_s, intent: lock["intent"])
        end
        @failing = nil
        listed
      rescue TTY::Command::ExitError, JSON::ParserError => e
        failing(e)
        []
      rescue SystemCallError
        missing
        []
      end

      # @return [Boolean] exit 0; false on exit 1, which is a refusal
      def run(*args, dir:)
        return true if @off

        result = @command.run!("alock", *args, "--dir", dir, env: { "AGENT_ID" => @id })
        @mutex.synchronize { @snapshot = nil }
        # 1 is a refusal; anything above is alock failing, which is said, and
        # counts as a refusal too: a plan nobody could check is left alone.
        if result.exit_status > 1
          left = args.first == "release" ? "; #{args[1]} stays held until the engine exits" : ""
          UI.log("alock #{args.first} #{args[1]} failed: #{(result.err.to_s + result.out.to_s).lines.first.to_s.strip}#{left}",
            level: :warn)
        end
        result.success?
      rescue SystemCallError
        missing
        true
      end

      # Said once per failure, not on every tick it lasts: the listing is
      # asked for every few seconds, and the same line each time buried the
      # log. A listing that works again clears it.
      #
      # @param error [Exception]
      # @return [void]
      def failing(error)
        # TTY::Command's message is the command line first; the reason is in
        # the stderr lines after it.
        reason = error.message.lines.map(&:strip).reject(&:empty?).find { it.start_with?("stderr:") } ||
                 error.message.lines.first.to_s.strip
        return if @failing == reason

        @failing = reason
        UI.log("alock list failed, plans unchecked until it works: #{reason}", level: :warn)
      end

      # @return [void]
      def missing
        return if @off

        @off = true
        UI.log("alock is not installed: plans are not checked against agents outside openlanes", level: :warn)
      end

      # The folder and everything in it: a directory scope covers its
      # contents, and the folder's own files are what the agents write.
      #
      # @param dir [String]
      # @return [String] relative to the folder's parent, where alock runs
      def scope(dir) = "#{File.basename(dir)}/**"

      # @param path [String]
      # @return [String]
      def real(path) = File.exist?(path) ? File.realpath(path) : File.expand_path(path)

      # @return [Boolean]
      def inside?(path, tree) = path == tree || path.start_with?("#{tree}/")

      # @return [String]
      def relative(path, tree) = path == tree ? "" : path.delete_prefix("#{tree}/")

      # alock's own rule: two scopes conflict when either one's literal part
      # contains the other's, and "" (the whole tree) contains everything.
      #
      # @param path [String]
      # @param fixed [String]
      # @return [Boolean]
      def overlap?(path, fixed)
        fixed.empty? || path.empty? || path == fixed ||
          path.start_with?("#{fixed}/") || fixed.start_with?("#{path}/")
      end
    end
  end
end
