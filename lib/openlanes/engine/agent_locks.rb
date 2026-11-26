# frozen_string_literal: true

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
    # The register is reached only through {Locking.adapter}: this class
    # decides what the engine claims and whose locks count, and the adapter
    # alone knows how alock is asked. A lock ends with the engine that took
    # it. A machine without alock has no agent using it either, and the
    # engine carries on without it, said once.
    #
    # Shared by the dispatcher's threads: every piece of state it keeps (the
    # listing, the failure last said, whether alock is missing) changes
    # under one mutex.
    class AgentLocks
      # How long one listing answers for. The dispatcher asks on every
      # one-second tick, and each answer starts a Ruby process.
      FRESH = 5

      # @param root [String] the repository whose plans are locked
      # @param id [String] the agent id the engine's own locks carry
      # @param own [Array<String>] the engine's agents, who claim with
      #   `AGENT_ID=<name>` or `<name>-<suffix>` as their prompt tells them to
      # @param adapter [#list, #acquire, #release] see {Locking::Adapter}
      # @param clock [#call] monotonic seconds
      def initialize(root:, id: Locking.holder, own: [], adapter: Locking.adapter, clock: -> { UI.monotonic })
        @root = File.realpath(root)
        @id = id
        @own = own
        @adapter = adapter
        @clock = clock
        @mutex = Mutex.new
        @failing = nil
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
      # @return [Locking::Lock, nil]
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
      # @return [Locking::Lock, nil]
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
        run(:acquire, scope(dir), intent, dir: File.dirname(dir))
      end

      # @param dir [String] the plan folder, as it was named when acquired
      # @return [void]
      def release(dir)
        run(:release, scope(dir), dir: File.dirname(dir))
      end

      private

      # @param agent [String] a lock's holder
      # @return [Boolean] the engine itself, one of its agents, or a sub-agent of one
      def ours?(agent) = agent == @id || @own.any? { agent == it || agent.start_with?("#{it}-") }

      # @return [Array<Locking::Lock>] every active lock, at most {FRESH} seconds old
      def held
        @mutex.synchronize do
          next [] if @off
          next @snapshot if @snapshot && @clock.call - @taken_at < FRESH

          @snapshot = list
          @taken_at = @clock.call
          @snapshot
        end
      end

      # Called with the mutex held.
      #
      # @return [Array<Locking::Lock>]
      def list
        listed = @adapter.list(@root)
        @failing = nil
        listed
      rescue Locking::Unreadable => e
        failing(e.message)
        []
      rescue Locking::Unavailable
        missing
        []
      end

      # @return [Boolean] done; false when refused, or when alock failed,
      #   since a plan nobody could check is left alone
      def run(action, *args, dir:)
        return true if @mutex.synchronize { @off }

        outcome = @adapter.public_send(action, *args, dir:, as: @id)
        @mutex.synchronize { @snapshot = nil }
        say_failed(action, args.first, outcome) if outcome.failed?
        outcome.done?
      rescue Locking::Unavailable
        @mutex.synchronize { missing }
        true
      end

      # @return [void]
      def say_failed(action, scope, outcome)
        left = action == :release ? "; #{scope} stays held until the engine exits" : ""
        UI.log("alock #{action} #{scope} failed: #{outcome.message}#{left}", level: :warn)
      end

      # Said once per failure, not on every tick it lasts: the listing is
      # asked for every few seconds, and the same line each time buried the
      # log. A listing that works again clears it. Called with the mutex held.
      #
      # @param reason [String]
      # @return [void]
      def failing(reason)
        return if @failing == reason

        @failing = reason
        UI.log("alock list failed, plans unchecked until it works: #{reason}", level: :warn)
      end

      # Called with the mutex held.
      #
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
