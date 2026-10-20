# frozen_string_literal: true

module OpenLanes
  module Engine
    # Drives specialist agents over a `.plans` tree until nothing is left to
    # dispatch.
    #
    # The loop itself is {Dispatcher}. This holds what the loop needs about
    # the run: the tree and its scope, the roster, the executor, how many run
    # at once, where each plan is checked out, and how a finished plan is
    # published. Blocked plans (⭕ 🛑 💣) are stepped around, never assigned,
    # and while a 💣 stands nothing new is assigned at all (plan 009).
    class Runner
      # What one agent did to one plan.
      Attempt = Data.define(:ordinal,
        :agent,
        :from,
        :to,
        :ok,
        :note,
        :up,
        :down,
        :subagents,
        :delegated,
        :seconds,
        :round,
        :file,
        :model,
        :status) do
        def initialize(round: 1, file: "", model: nil, status: nil, **rest) = super

        # @return [Boolean] whether the plan actually moved
        def advanced? = ok && from != to
      end

      # One unit of work: an agent, a plan, and the checkout it happens in.
      # `refresh` is what bringing the checkout up to date did, nil when
      # nothing was tried (shared isolation, a dry run, a partner already in it).
      Task = Data.define(:agent, :subject, :root, :checkout, :round, :refresh) do
        def initialize(refresh: nil, **rest) = super

        # @return [Hash] columns for the log
        def log_fields
          { plan: subject.feature.ordinal.to_s, status: subject.status.to_s,
           agent: agent.name, round: format("%02d", round) }
        end
      end

      # @param rounds [Integer, nil] `--rounds`, capping each agent's own
      # @param state [OpenLanes::Engine::StateFile, nil]
      # @param sleeper [Proc]
      # @param on_board [Proc, nil]
      # @param claims [OpenLanes::Live::Claims, nil] plan claims shared with
      #   other machines; nil when the run is not live, and every plan is ours
      # @param stay [Boolean] idle past fixed points until a person stops
      #   the run; see {Dispatcher#done?}
      # @param rescan [Integer] seconds between rescans while idle
      # @param watch [OpenLanes::Engine::PrWatch, nil] see {Dispatcher#initialize}
      # @param ignore_bombs [Boolean] `--ignore-bombs`: a 💣 halts nothing
      # @param aging_since [Date, nil] `plans.aging_since`, the floor of every
      #   blocked plan's clock
      # @param verification [OpenLanes::Engine::Verification::Driver, nil]
      #   what a 🧪 plan is run through (plan 014); nil when the run publishes
      #   nothing, and an approved plan then finishes at 👀
      # @param journal [OpenLanes::Engine::EventJournal, nil] the progress
      #   journal each engine event is appended to; nil keeps none
      # @param merging [OpenLanes::Engine::Merging, nil] what a 🏁 plan's
      #   pull requests go through once palpatine has ruled; nil when the
      #   run publishes nothing
      def initialize(tree:, executor:, agents: Agents::Registry.new, isolation: :shared, jobs: 1, worktree: nil,
        plans: nil, publisher: nil, dry_run: false, rounds: nil, state: nil,
        sleeper: ->(seconds) { sleep(seconds) }, on_board: nil, claims: nil, stay: false, rescan: Dispatcher::RESCAN,
        watch: nil, ignore_bombs: false, aging_since: nil, extensions: nil, verification: nil, journal: nil,
        merging: nil)
        @tree = tree
        @executor = executor
        @agents = agents
        @isolation = isolation
        @worktree = worktree
        @plans = plans
        @publisher = publisher
        @dry_run = dry_run
        @rounds = rounds
        @state = dry_run ? nil : state
        @sleeper = sleeper
        @on_board = on_board
        @claims = claims
        @stay = stay
        @rescan = rescan
        @watch = watch
        @ignore_bombs = ignore_bombs
        @aging_since = aging_since
        @extensions = extensions
        @verification = verification
        @journal = dry_run ? nil : journal
        @merging = merging
        @would_bomb = []
        @attempts = []
        @dropped = []
        @jobs = isolated? ? jobs : 1
      end

      attr_reader :jobs, :worktree, :tree, :attempts, :executor, :agents

      # @return [OpenLanes::Engine::Verification::Driver, nil]
      attr_reader :verification

      # @return [OpenLanes::Engine::Merging, nil]
      attr_reader :merging

      # A new concurrency limit, from the copilot's `/concurrency N`. Nothing
      # running is stopped: the dispatcher fills only while fewer agents run
      # than the limit, so a lower one takes effect as agents finish.
      #
      # @param count [Integer] at least 1
      # @return [void]
      # @raise [OpenLanes::Error] under `--isolation shared`, where every agent
      #   works in one checkout and a second would write over the first
      def jobs=(count)
        raise OpenLanes::Error, "concurrency must be a whole number of at least 1, not #{count.inspect}" unless count.is_a?(Integer) && count >= 1
        if !isolated? && count != 1
          raise OpenLanes::Error, "this run is --isolation shared: one checkout, one agent at a time, so concurrency stays 1"
        end

        @jobs = count
      end

      # @return [Boolean]
      def isolated? = @isolation == :worktree

      # @return [Boolean]
      def dry_run? = @dry_run

      # Whether a finished build is pushed and its pull request opened. Not
      # with `--isolation shared` or `--no-git-push`, the local-only runs, where
      # a plan can never hold the open pull request 🟢 requires.
      #
      # @return [Boolean]
      def publishes? = !@publisher.nil?

      # @return [String] the repository root
      def root = isolated? ? worktree.root : shared_root

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def in_scope?(subject)
        ordinal = subject.feature.ordinal
        !@dropped.include?(ordinal.to_s) && (@plans.nil? || @plans.include?(ordinal))
      end

      # Take a plan out of this run, as when another machine now holds it.
      #
      # @param ordinal [#to_s]
      # @return [void]
      def drop_plan(ordinal) = @dropped |= [ordinal.to_s]

      # @param ordinal [#to_s]
      # @return [Boolean] whether {#drop_plan} took it out of this run
      def dropped?(ordinal) = @dropped.include?(ordinal.to_s)

      # Let another machine take the plan: a person stopped it here.
      #
      # @param ordinal [#to_s]
      # @return [void]
      def release(ordinal) = @claims&.release(ordinal)

      # @return [Array<OpenLanes::Plans::Subject>]
      def in_scope = tree.subjects.select { |s| in_scope?(s) }

      # Widen a run scoped by `--plan` to one more plan, from the page's
      # "Choose an existing plan". An unscoped run already has every plan.
      #
      # @param ordinal [OpenLanes::Plans::Ordinal]
      # @return [Boolean] whether the scope grew
      def add_plan(ordinal)
        @dropped.delete(ordinal.to_s)
        return false if @plans.nil? || @plans.include?(ordinal)

        @plans << ordinal
        true
      end

      # Whether another machine holds the plan (W26). Such a plan is stepped
      # around, as a blocked one is.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def foreign?(subject)
        !@claims.nil? && @claims.foreign?(subject.feature.ordinal)
      rescue Live::Unavailable => e
        claims_unavailable(e)
        false
      end

      # Take the plan before an agent starts on it. With Redis gone nothing
      # new starts (W31): this machine cannot tell whether another one sharing
      # the Redis already took the plan, and two machines building one spec is
      # the collision the claim exists to prevent. Agents already running keep
      # going. A run with no Redis at all has no claims and works alone.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean] whether this machine may work it
      def claim(subject)
        claimed = @claims.nil? || @claims.claim(subject.feature.ordinal)
        @claims_down = nil
        claimed
      rescue Live::Unavailable => e
        claims_unavailable(e)
        false
      end

      # Where the plan's checkout lives when the run isolates, whether or not
      # it has been made.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [String, nil]
      def checkout_path(subject) = isolated? ? worktree.path_for(subject.feature) : nil

      # Run until nothing is dispatchable, or, staying, until a person stops
      # it.
      #
      # @yieldparam dispatcher [OpenLanes::Engine::Dispatcher] before it runs, so a
      #   console can attach itself and reach the running jobs
      # @return [Array<OpenLanes::Engine::Runner::Attempt>]
      def call
        dispatcher = Dispatcher.new(runner: self,
          state:    @state,
          rounds:   @rounds,
          sleeper:  @sleeper,
          on_board: @on_board,
          stay:     @stay,
          rescan:   @rescan,
          watch:      @watch,
          extensions: @extensions,
          journal:    @journal)
        yield dispatcher if block_given?
        @attempts = dispatcher.run
      end

      # @return [Array<OpenLanes::Plans::Subject>]
      def blocked = in_scope.select { |s| Dispatcher::BLOCKED.include?(s.status.key) }

      # Age the blocked plans in scope (plan 009): bomb the ones others wait
      # on, defer the ones nobody does. A dry run fires nothing, and
      # remembers what it would have bombed so it halts as a real run would.
      #
      # @param except [Array<String>] ordinals an agent or a drain is in
      # @param now [Time]
      # @return [OpenLanes::Lifecycle::Aging::Result]
      def age!(except: [], now: Clock::System.now)
        subjects = in_scope.reject { except.include?(it.feature.ordinal.to_s) || foreign?(it) }
        result = Lifecycle.age(tree:, subjects:, since: @aging_since, now:, commit: !dry_run?)
        @would_bomb = result.bombed if dry_run?
        result
      end

      # Plans in scope that are 💣, or on a dry run would have become one.
      #
      # @return [Array<OpenLanes::Plans::Subject>]
      def bombs
        in_scope.select { it.status.key == :bomb || @would_bomb.include?(it.feature.ordinal.to_s) }
      end

      # The bombs that stop new work right now: none under `--ignore-bombs`,
      # and none whose halt a person lifted from the page until it lapses.
      #
      # @param now [Time]
      # @return [Array<OpenLanes::Plans::Subject>]
      def halted_by(now: Clock::System.now)
        return [] if @ignore_bombs

        bombs.reject { Plans::PlanState.for(it.feature.path).resumed?(now:) }
      end

      # @return [Boolean] whether a 💣 keeps every new agent from starting
      def halted? = !halted_by.empty?

      # Plans in scope the dependency gate holds back, with the reason: a
      # dependency that is not done yet, or a cycle that no order can break.
      # A plan with no `depends_on:` key is never held, nor is one already
      # parked, whose own state says more than its dependencies do.
      #
      # @param deps [OpenLanes::Plans::Dependencies] the graph to ask; the
      #   dispatcher passes the one it gated with, so both say the same thing
      # @return [Hash{String => String}] ordinal => "waiting on 034.00" or "cycle: ..."
      def held(deps = dependencies)
        in_scope.each_with_object({}) do |subject, out|
          next if Plans::StateMachine::SETTLED.include?(subject.status.key)

          ordinal = subject.feature.ordinal.to_s
          reason = deps.reason(ordinal) and out[ordinal] = reason
        end
      end

      # The dependency graph judged by the states this run acts on. A real run
      # has reconciled every folder name before it asks, so the names are the
      # states. A dry run renames nothing, so it judges each plan by the state
      # reconciliation would give it, as {Dispatcher} does when it picks an
      # agent; otherwise an In Review prerequisite whose pull requests have
      # all merged would read as done to one and open to the other.
      #
      # @param except [Array<String>] ordinals reconciliation leaves alone
      #   (an agent is in them), judged by their folder's name; plans another
      #   machine holds are always left alone
      # @return [OpenLanes::Plans::Dependencies]
      def dependencies(except: [])
        return tree.dependencies unless dry_run?

        leave = except.map(&:to_s)
        # Every plan, archived ones included, as {Plans::Tree#dependencies}
        # does: a shipped prerequisite sits in `archive/`.
        Plans::Dependencies.new(tree.everything,
          status_of: lambda { |subject|
            untouched = leave.include?(subject.feature.ordinal.to_s) || foreign?(subject)
            untouched ? subject.status : effective_status(subject)
          })
      end

      # The state a plan's contents justify, which reconciliation would rename
      # its folder to: its lane's skip first, then what `resync dirs` reads.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [OpenLanes::Plans::Status]
      def effective_status(subject) = Lifecycle::Lanes.target(subject) || Lifecycle::Resync::Dirs.target(subject)

      # @return [Boolean]
      def settled? = in_scope.all? { |s| Plans::StateMachine::SETTLED.include?(s.status.key) }

      # A dry run gets the shared root whatever the isolation says: nothing
      # runs in the checkout, and `git worktree add` is a side effect a
      # preview must not have. It also fails outright when the plan's branch
      # is the one checked out where the run was typed, which is where a dry
      # run of that plan is typed.
      #
      # A worktree is brought up to date with the default branch first (see
      # {Vcs::Refresh}), here rather than on the agent's thread, so no partner
      # can start in the same checkout while git is rewriting it.
      #
      # @param refresh [Boolean] false when another agent is already working
      #   in the plan's checkout, which must not move under it
      # @param hold [String, nil] see {Vcs::Refresh#call}
      # @return [OpenLanes::Engine::Runner::Task]
      def prepare(agent, subject, round, refresh: true, hold: nil)
        return Task.new(agent:, subject:, root: shared_root, checkout: nil, round:) if !isolated? || dry_run?

        checkout = worktree.checkout_for(subject.feature)
        outcome = worktree.refresh(checkout, hold:) if refresh
        Task.new(agent:, subject:, root: checkout.path, checkout:, round:, refresh: outcome)
      end

      # Push a finished build and record the pull request it opened in the
      # plan's `pull-requests.md`, the row 🟢 is judged by. A push to a pull
      # request the plan already had records nothing: the row is there, and a
      # second copy of it would read as a second pull request.
      #
      # @param task [OpenLanes::Engine::Runner::Task]
      # @param subject [OpenLanes::Plans::Subject] the plan in the main tree
      # @return [OpenLanes::Vcs::Publisher::Publication, nil] nil when the run
      #   publishes nothing or the checkout holds no change
      def publish(task, subject)
        return nil unless @publisher && task.checkout&.dirty?

        publication = @publisher.publish(checkout: task.checkout, subject:)
        record_pull_request(subject.feature.path, publication) if publication.published? && !publication.updated
        publication
      end

      private

      # @return [String]
      def shared_root = File.dirname(tree.dir)

      # @param error [OpenLanes::Live::Unavailable]
      # @return [void]
      # Said once per outage: every plan asks on every tick, and the same
      # line a hundred times buries the moment Redis went away.
      def claims_unavailable(error)
        return if @claims_down == error.message

        @claims_down = error.message
        UI.log("claims unchecked, starting nothing new until Redis answers: #{error.message}", level: :warn)
      end

      # @return [void]
      def record_pull_request(path, publication)
        number = publication.url.to_s[%r{/pull/(\d+)}, 1]
        rows = Plans::PullRequests.new(dir: path).all.map { |pr|
          { number: pr.number, title: pr.title, url: pr.url, state: pr.state, body: "" }
        }
        rows << { number:, title: publication.title, url: publication.url, state: "Open 🟡", body: "" }
        Plans::PullRequests.upsert(File.join(path, Plans::PullRequests::FILENAME), rows)
      end
    end
  end
end
