# frozen_string_literal: true

module OpenLanes
  module Engine
    # `openlanes run` without the command: narrow the roster and the plans,
    # check the pairing makes sense, set the run up (isolation, log,
    # state file, live board, control room), build the {Runner}, run it to a
    # fixed point, and report what it did.
    #
    # Progress, the startup box and the closing report draw on STDERR and the
    # attempts list prints on STDOUT, as the run happens. The answer is the
    # exit status the command ends with.
    class RunWorkflow
      include UI
      include Dry::Monads[:result]
      include Dry::Monads::Do.for(:call)

      # `--prompt` shorter than this that names an existing file is read.
      PROMPT_PATH_LIMIT = 80

      # @param tree [OpenLanes::Plans::Tree]
      # @param origin [String] the directory the command was typed in, which
      #   a path typed into `--prompt` is relative to
      # @param options [Hash] the `run` flags as dry-cli parsed them, over
      #   `.openlanes.yml`
      def initialize(tree:, origin: Dir.pwd, **options)
        @tree = tree
        @origin = origin
        @options = options
        @root = options[:root] || File.dirname(tree.dir)
        @dry_run = options.fetch(:dry_run, false)
        @quiet = options.fetch(:quiet, false)
        @startup = []
      end

      # Option precedence, quietest to loudest: the built-in default, then
      # `.openlanes.yml` (`jobs`, and the `commands.run` section), then the
      # flag actually typed. {CLI::Base.default_params} folded the file in.
      #
      # @return [Dry::Monads::Result] Success(Integer) the exit status, or
      #   Failure({Refusal}) for flags that contradict each other or the tree
      def call
        yield prompt_needs_agent
        agents = yield roster
        plans  = yield scope
        yield assignable(agents, plans) if @options[:agent]
        yield isolatable
        yield logging

        prepare(plans)
        live = yield live_for(agents)
        web  = yield web_for(live)
        runner = runner_for(agents, plans, live, web)
        startup_box

        started  = UI.monotonic
        attempts = run(runner, live, web)
        Success(finish(runner, attempts, seconds: UI.monotonic - started))
      end

      private

      # @param message [String]
      # @param status [Integer]
      # @return [Dry::Monads::Result::Failure]
      def refusal(message, status) = Failure(Refusal.new(message:, status:))

      # @return [Dry::Monads::Result]
      def prompt_needs_agent
        return Success(nil) unless @options[:prompt] && !@options[:agent]

        refusal("--prompt only works with --agent: it speaks to one agent, and without " \
                "that restriction every agent in the round would hear it.",
          64)
      end

      # `--agent` restricts the roster for assignments, not just chaining, or a
      # flag like `--prompt` aimed at one agent leaks to the whole round.
      # Each `--skip` name is checked against the full roster, so a misspelled
      # one is a refusal rather than a silent no-op — the same reasoning
      # `--plan` applies to numbers.
      #
      # @return [Dry::Monads::Result] Success(OpenLanes::Agents::Registry)
      def roster
        all = OpenLanes::Agents.registry
        only = @options[:agent]
        skips = @options[:skip].to_s.split(",").map(&:strip).reject(&:empty?)

        ([only].compact + skips).each { |name| all.find(name) or return refusal(unknown_agent(all, name), 65) }
        if only && skips.include?(only)
          return refusal("--agent #{only} and --skip #{only} contradict each other: " \
                         "one asks for only this agent, the other for anything but.",
            64)
        end

        agents = only ? all.only(only) : all
        Success(skips.empty? ? agents : agents.without(*skips))
      end

      # @param all [OpenLanes::Agents::Registry]
      # @param name [String]
      # @return [String]
      def unknown_agent(all, name) = "No agent called #{name}.\n\nKnown: #{all.all.map(&:name).join(", ")}"

      # `--plan` names the whole point of scoping: a skill that just minted
      # N folders hands off exactly those, not the tree. A typo'd or already-
      # settled number silently running the whole tree instead is the failure
      # this exists to prevent, so an unknown one is refused rather than
      # dropped.
      #
      # @return [Dry::Monads::Result] Success(Array<OpenLanes::Plans::Ordinal>), or Success(nil) for all
      def scope
        return Success(nil) unless @options[:plan]

        known = @tree.subjects.map { |s| s.feature.ordinal }
        ordinals = @options[:plan].split(",").map(&:strip).reject(&:empty?).map do |token|
          ordinal = Plans::Ordinal.parse(token)
          unless ordinal && known.include?(ordinal)
            return refusal("No plan #{token} in #{@tree.dir}.\n\nKnown: #{known.join(", ")}", 66)
          end

          ordinal
        end
        Success(ordinals)
      end

      # `--agent` narrowing the round to nobody used to exit 0 in silence —
      # "0 plans addressed", green box, no hint that the agent named simply
      # does not handle any in-scope plan's state. Someone who typed both an
      # agent and a plan meant them to meet, so a pairing that cannot happen
      # is refused up front with the agent that would actually take each plan.
      #
      # @param agents [OpenLanes::Agents::Registry] already narrowed to the one agent
      # @param plans [Array<OpenLanes::Plans::Ordinal>, nil]
      # @return [Dry::Monads::Result]
      def assignable(agents, plans)
        name   = @options[:agent]
        agent  = agents.find(name)
        active = @tree.subjects.select do |s|
          (plans.nil? || plans.include?(s.feature.ordinal)) && !Plans::StateMachine::SETTLED.include?(s.status.key)
        end
        return Success(nil) if active.empty? || active.any? { |s| agent.handles?(s.status) }

        refusal("#{name} handles #{handled(agent).join(", ")}, and no plan in scope is there:\n\n" \
                "#{takers(active).join("\n")}\n\nName the agent that takes these states, or drop --agent.",
          65)
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @return [Array<String>] the states it handles, as a person reads them
      def handled(agent)
        agent.handles.map { |k| OpenLanes::Plans::STATUS_BY_KEY[k]&.then { |st| "#{st.emoji} #{st.label}" } || k }
      end

      # @param active [Array<OpenLanes::Plans::Subject>]
      # @return [Array<String>] each plan's state, and who would take it
      def takers(active)
        roster = OpenLanes::Agents.registry
        active.map do |s|
          names = OpenLanes::Agents::Routing.filter(roster.for_status(s.status), s).map(&:name)
          verb  = names.size == 1 ? "takes" : "take"
          "  #{s.feature.ordinal} is #{s.status.emoji} #{s.status.label}" \
            "#{" - #{names.join(" and ")} #{verb} it" unless names.empty?}"
        end
      end

      # @return [Symbol] :worktree or :shared
      def isolation = @options.fetch(:isolation, "worktree").to_sym

      # @return [Dry::Monads::Result]
      def isolatable
        return Success(nil) unless isolation == :worktree && !OpenLanes::Vcs.worktree(root: @root).repository?

        refusal("#{@root} is not a git repository, so plans cannot be isolated.\n\n" \
                "Run with --isolation shared to work in one tree, serially.",
          66)
      end

      # Opens the log every event of the run is written to, the one the
      # control room's server will write to as well (it is handed the same
      # settings through {Web::Launcher#env}). Logged as `engine`, so its
      # lines and the server's tell themselves apart.
      #
      # The project root rather than `--root`: `--root` is where agents
      # work, and the log belongs with the `.plans` it reports on.
      #
      # @return [Dry::Monads::Result]
      def logging
        settings = Log.setup(Log::Settings.from(@options, root: File.dirname(@tree.dir)), name: "engine")
        Log.logger.info("run starting", root: @root, dry_run: @dry_run)
        Success(settings)
      rescue Log::Invalid => e
        refusal(e.message, 64)
      end

      # The warnings that must land before the first agent,
      # the state file, and a clean control file.
      #
      # @param plans [Array<OpenLanes::Plans::Ordinal>, nil]
      # @return [void]
      def prepare(plans)
        startup("Log", UI.log_path)
        credentials unless @dry_run || @quiet
        spec_warning(plans) unless @quiet
        sync_labels if publishing?

        # The state file is what a harness that dies leaves for the next one.
        # It sits in .plans/ so a reboot keeps it, and it is ignored by name
        # so it never rides along in a commit. Editing somebody's .gitignore
        # is announced, the once it happens. The runner drops the file on a
        # dry run, which is why it can be built unconditionally.
        if !@dry_run && StateFile.ensure_ignored!(@root) && !@quiet
          info("Added #{StateFile::IGNORE.join(" and ")} to .gitignore: the run keeps its state there.")
        end

        # Control files from a previous run would otherwise be read as orders
        # to this one.
        Execution::Control.reset!
      end

      # @return [Boolean] whether this run opens and labels pull requests;
      #   the same test {#publisher_for} applies, without its warning
      def publishing? = isolation == :worktree && @options[:git_push] != false

      # Every review label on the repository, in R3's colours, before any
      # pull request is labelled (R3). Once per run. A `gh` that cannot be
      # reached is warned about rather than refused: labelling creates a
      # missing label on first use anyway, so the run loses colours, not work.
      # Against `--root`'s repository, the one the publisher opens pull
      # requests on, not whichever checkout the engine was started from.
      #
      # @return [void]
      def sync_labels
        changes = Vcs.label_sync(root: @root).call(dry_run: @dry_run).select(&:write?)
        return if changes.empty? || @quiet

        lead = @dry_run ? "Dry run: would sync review labels" : "Synced review labels"
        info("#{lead}:\n#{changes.map { "  #{it}" }.join("\n")}")
      rescue OpenLanes::Error => e
        warn("Review labels not synced: #{e.message}") unless @quiet
      end

      # @return [void]
      def credentials
        notice = Execution.credentials_notice
        warn(notice) if notice
      end

      # A spec.md whose frontmatter does not parse routes as if it had none:
      # lane full, every override dropped. An eval agent's unquoted backtick
      # sent a quick-lane rename to research that way, and said nothing.
      # {Plans::Spec#problems} already knew; say it before agents are assigned.
      #
      # @param plans [Array<OpenLanes::Plans::Ordinal>, nil] the --plan ordinals, nil for all
      # @return [void]
      def spec_warning(plans)
        lines = @tree.subjects.filter_map do |subject|
          ordinal = subject.feature.ordinal
          next if plans && !plans.include?(ordinal)

          problems = Plans::Spec.for(subject).problems
          "#{ordinal}: #{problems.join("; ")}" unless problems.empty?
        end
        return if lines.empty?

        warn("spec.md frontmatter ignored in part, so these plans route on defaults:\n#{lines.join("\n")}")
      end

      # The live board (W6, W13, W26), when this run has one: not on a dry
      # run, which must leave nothing behind, and not without Redis, where
      # the run goes on exactly as it did before there was a page. Either
      # way it is said once, so a page that never updates is not a mystery.
      #
      # @param agents [OpenLanes::Agents::Registry]
      # @return [Dry::Monads::Result] Success(OpenLanes::Live::Session or nil)
      def live_for(agents)
        if @dry_run
          warn("Dry run: the live board is off, so nothing is published to Redis and no plan is claimed.") unless @quiet
          return Success(nil)
        end

        config = Config.current
        store = Live.connect(Live.redis_url(option: @options[:redis_url], config:))
        Success(Live.session(store:, root: @root, tree: @tree, agents:, project: config.project).tap do |session|
          startup("Live board", session.described)
        end)
      rescue Live::Unavailable => e
        without_live(e.message)
      end

      # A live board this run cannot do without: `run` goes on headless.
      #
      # @param message [String] why there is no board
      # @return [Dry::Monads::Result] Success(nil)
      def without_live(message)
        unless @quiet
          warn("#{message}\n\nThe run goes on without the live board: no page, no commands from it, and no " \
               "plan claims shared with other machines. Start redis-server, or pass --redis-url.")
        end
        Success(nil)
      end

      # The control room (W1, W7): `openlanes web` as its own process beside
      # the engine, reading the board this run publishes. Only with a live
      # board to read, so a dry run, a run without Redis and `--no-web` all
      # stay headless. A server that does not come up is reported and left
      # out; the run is the agents' work, and the page is a view of it.
      #
      # @param live [OpenLanes::Live::Session, nil]
      # @return [Dry::Monads::Result] Success(OpenLanes::Web::Launcher or nil)
      def web_for(live)
        return Success(nil) if live.nil? || @options[:web] == false

        port = Integer(@options[:port] || OpenLanes::Web::DEFAULT_PORT)
        web = OpenLanes::Web.launcher(root: @root, plans_dir: @tree.dir, port:, redis_url: live.store.url).start
        unless web.ready?
          web.stop
          return without_web(web, live)
        end

        startup("Control room", web.port == port ? web.url : "#{web.url} (#{port} was taken)")
        OpenLanes::Web.open(browser_url(web)) unless @options[:open] == false
        Success(web)
      end

      # @param web [OpenLanes::Web::Launcher] one that did not answer
      # @param _live [OpenLanes::Live::Session]
      # @return [Dry::Monads::Result] Success(nil)
      def without_web(web, _live)
        warn("The control room did not answer on #{web.url}, so the run goes on without it. Its log: #{web.log}") unless @quiet
        Success(nil)
      end

      # Where the browser is sent once the control room answers.
      #
      # @param web [OpenLanes::Web::Launcher]
      # @return [String]
      def browser_url(web) = web.url

      # @param agents [OpenLanes::Agents::Registry]
      # @param plans [Array<OpenLanes::Plans::Ordinal>, nil]
      # @param live [OpenLanes::Live::Session, nil]
      # @param web [OpenLanes::Web::Launcher, nil]
      # @return [OpenLanes::Engine::Runner]
      def runner_for(agents, plans, live, web)
        worktree = (OpenLanes::Vcs.worktree(root: @root) if isolation == :worktree)
        publisher = publisher_for(@root, isolation)
        Engine.runner(
          tree:         @tree,
          agents:,
          isolation:,
          jobs:         (@options[:jobs] || UI.default_jobs).to_i,
          plans:,
          state:        Engine.state_file(@tree),
          worktree:,
          rounds:       @options[:rounds]&.to_i,
          executor:     executor,
          dry_run:      @dry_run,
          publisher:,
          verification: verification_for(publisher, worktree),
          on_board:     live&.on_board,
          claims:       live&.claims,
          ignore_bombs: @options.fetch(:ignore_bombs, false),
          aging_since:  Config.current.aging_since,
          **staying(web)
        )
      end

      # @return [OpenLanes::Execution::Executor]
      def executor
        Execution.executor(root:         @root,
          timeout:      @options[:timeout]&.to_i,
          dry_run:      @dry_run,
          instructions: instructions_from(@options[:prompt]),
          model:        @options[:model],
          max_tokens:   @options[:max_tokens]&.to_i,
          lean:         !@options[:user_config])
      end

      # `--prompt` takes the instructions themselves or a file holding them.
      # A short argument naming an existing file is read; anything else is
      # the text, so a sentence that happens to match a filename in the
      # project is not silently swapped for that file once it is long enough
      # to be a sentence.
      #
      # @param prompt [String, nil]
      # @return [String, nil]
      def instructions_from(prompt)
        path = prompt && File.expand_path(prompt, @origin)
        return prompt unless prompt && prompt.length < PROMPT_PATH_LIMIT && File.file?(path)

        File.read(path)
      end

      # The one thing this harness does that leaves the machine — pushing a
      # branch and opening its pull request — so it takes one more thing to
      # turn on than everything else here: not being a dry run is not enough,
      # isolation has to actually give each plan a branch of its own too.
      #
      # `nil` is how {Runner} is told to leave a finished worktree alone; it
      # is what `--no-git-push` asks for, and what a shared tree gets
      # by construction, since there is no separate branch there to push.
      #
      # @param root [String]
      # @param isolation [Symbol]
      # @return [OpenLanes::Vcs::Publisher, nil]
      def publisher_for(root, isolation)
        if isolation != :worktree || @options[:git_push] == false
          unless @quiet
            warn("No pull request will be opened (#{isolation == :worktree ? "--no-git-push" : "--isolation shared"}), " \
                 "so a finished build stays at 🟡 Building:\n🟢 Ready for Review needs an open pull request, " \
                 "and hansolo-reviewer reviews one.")
          end
          return nil
        end

        Vcs.publisher(root:, dry_run: @dry_run)
      end

      # Verification (plan 014) commits, comments and labels, so it runs
      # only where the build was published: a plan never pushed has no pull
      # request to verify, and a dry run changes nothing.
      #
      # @param publisher [OpenLanes::Vcs::Publisher, nil]
      # @param worktree [OpenLanes::Vcs::Worktree, nil]
      # @return [OpenLanes::Engine::Verification::Driver, nil]
      def verification_for(publisher, worktree)
        return nil if publisher.nil? || worktree.nil? || @dry_run

        github = Vcs.github
        config = Config.current
        outcome = Verification.outcome(root: @root,
          publisher:,
          github:,
          outcomes: PrOutcomes.new(tree_dir: @tree.dir, agents: Agents::Registry.new),
          agents: Agents::Registry.new,
          max_rejections: config.max_rejections)
        Verification::Driver.new(outcome:, worktree:, app: Apps.definition(config))
      end

      # What the runner is told about idling past its fixed points. With its
      # control room up the engine stays, since the page can answer a blocked
      # plan or create the next one at any moment, and a run that had ended
      # would leave the page talking to nobody. Headless, or with
      # `--until-settled`, it ends at the first fixed point.
      #
      # A staying run is also the one that watches the pull requests a person
      # merges (M4): it is still up when they do. A run that ends cannot wait
      # for a merge, so it names the pull requests it leaves unwatched instead.
      #
      # @param web [OpenLanes::Web::Launcher, nil] the control room, when it came up
      # @return [Hash] `stay:`, `rescan:` and `watch:` for {Runner}, or nothing
      def staying(web)
        return {} if web.nil? || @options[:until_settled]

        @stays = "The engine stays up with its control room: Stop All Local or Ctrl-C ends it."
        { stay: true, rescan: Dispatcher::RESCAN, watch: watch }
      end

      # The pull request watch a staying run carries, in human mode only: when
      # agents merge, nobody else's merge is worth waiting for. Kept apart from
      # {#staying} so {StartWorkflow}, which overrides that, cannot leave it behind.
      #
      # @return [OpenLanes::Engine::PrWatch, nil]
      def watch
        PrWatch.new(github: Vcs.github) if Config.current.human_merges? && !@dry_run
      end

      # The open pull requests a run that does not stay leaves for a person,
      # logged so the next `openlanes start` is known to be the one to watch them.
      #
      # @param runner [OpenLanes::Engine::Runner]
      # @return [void]
      def unwatched(runner)
        return if @stays || !Config.current.human_merges?

        open = runner.in_scope.flat_map { |s| s.pull_requests.select(&:open?).map { "#{s.feature.ordinal} ##{it.number}" } }
        return if open.empty?

        UI.log("not watching #{open.join(", ")}: openlanes start watches pull requests until they merge")
      end

      # One line of the startup box, kept until {#startup_box} draws it.
      #
      # @param label [String]
      # @param value [String, Array<String>] parts a narrow box may break between
      # @return [void]
      def startup(label, value) = @startup << [label, value]

      # Where the run writes, what it publishes to, and where its page is:
      # one Info box, drawn once all three are known. A line that does not
      # apply (no Redis, no control room) is left out, not drawn empty.
      #
      # @return [void]
      def startup_box
        return if @quiet || @startup.empty?

        info([UI.labelled(@startup), @stays].compact.join("\n\n"))
      end

      # The terminal hears the run as it happens, one appended line per
      # event, whether or not a control room is up: the page is the board,
      # and the terminal is its log. Nothing here redraws, so nothing can
      # draw over a box or over another line.
      #
      # @param runner [OpenLanes::Engine::Runner]
      # @param live [OpenLanes::Live::Session, nil]
      # @param web [OpenLanes::Web::Launcher, nil]
      # @return [Array<OpenLanes::Engine::Runner::Attempt>]
      def run(runner, live, web)
        narrator = UI.tap_log(Narrator.new) unless @quiet
        Execution.on_interrupt(signals:) { runner.call { |dispatcher| live&.attach(dispatcher) } }
      ensure
        UI.untap_log(narrator) if narrator
        live&.close
        web&.stop
      end

      # Signals that stop the run gracefully, the way the first Ctrl-C does.
      # TERM too: a run with its control room stays up like a service, and a
      # service manager stops a service that way.
      #
      # @return [Array<String>]
      def signals = %w[INT TERM]

      # The closing report. A halted run that exited 0 would read to a
      # script as a tree with nothing left to do, so a 💣 makes it 1 (N9).
      #
      # @param runner [OpenLanes::Engine::Runner]
      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @param seconds [Float] wall clock for the whole loop
      # @return [Integer] the exit status: 1 when any attempt failed, or
      #   when a 💣 halted the run
      def finish(runner, attempts, seconds:)
        unwatched(runner)
        report(runner, attempts, seconds:)
        bombs = runner.halted_by
        bomb_report(bombs)
        status = failures(attempts).empty? && bombs.empty? ? 0 : 1
        Log.logger.public_send(status.zero? ? :info : :warn,
          "run finished",
          attempts: attempts.size,
          failed:   failures(attempts).size,
          seconds:  seconds.round(1),
          exit:     status)
        status
      end

      # Named on STDERR even under --quiet: it is why the run exits 1.
      #
      # @param bombs [Array<OpenLanes::Plans::Subject>]
      # @return [void]
      def bomb_report(bombs)
        return if bombs.empty?

        names = bombs.map { |b| "  #{b.feature.ordinal} #{b.feature.title} — see blocked.md" }.join("\n")
        error("Halted: #{bombs.size} 💣 plan#{"s" unless bombs.size == 1} other plans wait on, " \
              "blocked too long:\n#{names}\n\n" \
              "Answer blocked.md, resume anyway from the control room, or re-run with --ignore-bombs.")
      end

      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @return [Array<OpenLanes::Engine::Runner::Attempt>]
      def failures(attempts) = attempts.reject(&:ok)

      # One line per attempt: the plan, who ran, which of that agent's rounds
      # it was, what moved, and the note. There is no round header because
      # the loop has no rounds of its own: each agent counts its own per
      # plan, so two agents on one plan can be on different numbers.
      #
      # @param runner [OpenLanes::Engine::Runner]
      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @param seconds [Float]
      # @return [void]
      def report(runner, attempts, seconds:)
        # What the run cost, on STDOUT with the attempts it belongs to, so a run
        # redirected to a file keeps its bill. A dry run spent nothing and gets
        # none of this.
        puts_report(attempts, (Engine.tally(attempts:, seconds:).render unless @dry_run))
        return if @quiet

        if Execution::Control.quit?
          warn("Stopped from the keyboard — q. Unfinished plans keep their state; " \
               "re-run to resume where they stand.")
        end

        summarize(runner, attempts)
        held_report(runner.held)
        blocked_report(runner.blocked)
      end

      # @param runner [OpenLanes::Engine::Runner]
      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @return [void]
      def summarize(runner, attempts)
        failed  = failures(attempts)
        summary = ["#{attempts.size} invocation#{"s" unless attempts.size == 1}", "#{attempts.count(&:advanced?)} advanced"]
        summary << (runner.isolated? ? "#{runner.jobs} at a time, one worktree each" : "serial, shared tree")
        summary << "#{runner.blocked.size} blocked" unless runner.blocked.empty?
        summary << "#{failed.size} failed" unless failed.empty?

        if @dry_run
          warn("Dry run — no agent was invoked.\n#{summary.join(" · ")}\n\nRe-run without --dry-run.")
        elsif failed.empty?
          success("#{summary.join(" · ")}#{"\n\nEvery plan is done or deliberately parked." if runner.settled?}")
        else
          error("#{summary.join(" · ")}\n\n#{failed.map { |f| "#{f.ordinal} #{f.agent}: #{f.note}" }.join("\n")}")
        end
      end

      # Plans the dependency gate held back, and why, so a run that stops at a
      # fixed point with work left says what it is waiting for.
      #
      # @param held [Hash{String => String}] ordinal => reason
      # @return [void]
      def held_report(held)
        return if held.empty?

        warn("#{held.size} plan#{"s" unless held.size == 1} held by dependencies:\n" +
             held.map { |ordinal, why| "  #{ordinal} #{why}" }.join("\n"))
      end

      # @param blocked [Array<OpenLanes::Plans::Subject>]
      # @return [void]
      def blocked_report(blocked)
        return if blocked.empty?

        warn("#{blocked.size} plan#{"s" unless blocked.size == 1} need a human decision:\n" +
             blocked.map { |b| "  #{b.feature.ordinal} #{b.status.emoji} #{b.feature.title} — see blocked.md" }.join("\n") +
             "\n\nWrite the answers into blocked.md, then: openlanes unblock " \
             "#{blocked.map { |b| b.feature.ordinal }.join(",")}")
      end

      # The attempts and the bill, one blank line before each part that has
      # anything in it. `puts []` prints an empty line, so a run with no
      # attempts used to open its report with two blank lines and a third
      # before the tally.
      #
      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @param tally [String, nil] nil prints none
      # @return [void]
      def puts_report(attempts, tally)
        lines = attempt_lines(attempts)
        puts("", *lines) unless lines.empty?
        puts("", tally) if tally
      end

      # The attempts list, padded into columns. Widths come from the rows
      # themselves, so the columns are as narrow as the run allows and still
      # square; tabs put every column on the next multiple of eight, so one
      # agent's name a character longer pushed a whole column a stop right.
      #
      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @return [Array<String>] one line per attempt, indented by two
      def attempt_lines(attempts)
        rows   = attempts.map { |a| [a.ordinal.to_s, a.agent.to_s, "[R:#{a.round}]", mark(a), a.note.to_s] }
        widths = rows.transpose.map { |column| column.map { |cell| UI.display_width(cell) }.max.to_i }
        rows.map do |cells|
          # The note is last and is left as it is: padding the final column
          # only adds trailing whitespace a copy-paste then carries.
          last = cells.size - 1
          "  #{cells.each_with_index.map { |cell, i| i == last ? cell : UI.fit(cell, widths[i] + 2) }.join}"
        end
      end

      # @param attempt [OpenLanes::Engine::Runner::Attempt]
      # @return [String] what the attempt did to its plan's state
      def mark(attempt)
        return "FAIL" unless attempt.ok
        return "#{attempt.from} -> #{attempt.to}" if attempt.advanced?

        "no change"
      end
    end
  end
end
