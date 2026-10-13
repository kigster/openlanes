# frozen_string_literal: true

require "tmpdir"

module OpenLanes
  module CLI
    # `openlanes run` — drive the specialist agents until the tree settles.
    class Run < Base
      desc "Run specialist agents over the plans; with the control room up it stays, else it ends when nothing changes"

      dry_run_option "Invoke no agent; print which agent would take which plan"
      option :rounds,
        desc: "Cap on rounds per agent per plan; each agent declares its own, at most 5 " \
              "(default: the agent's own)"
      option :timeout,
        desc: "Seconds before one agent is abandoned; only tightens an agent's own clock " \
              "(default: the agent's own, else 900)"
      option :agent, desc: "Only run this one agent"
      # `--prompt` shorter than this that names an existing file is read.
      PROMPT_PATH_LIMIT = 80

      option :prompt,
        desc: "Extra instructions appended to the agent's prompt (only with --agent); " \
              "a path to an existing text file under #{PROMPT_PATH_LIMIT} characters is read instead"
      option :skip,
        desc: "Never assign this agent; its plans wait, the rest of the pipeline runs. " \
              "Comma separated for several"
      option :model,
        desc: "Model for every agent this run, overriding each agent's own frontmatter and spec.md " \
              "(default: what the agent declares, else the CLI's default). Claude models above Opus run as Opus"
      option :user_config,
        type:    :boolean,
        default: false,
        desc:    "Start agents with your personal plugins, skills, hooks and MCP servers. " \
                 "Off by default: they cost every agent context and start-up time on every turn"
      option :max_tokens,
        desc: "Token budget per agent invocation, input plus output, sub-agents " \
              "included. The agent is told the number so it can finish inside it; the meter aborts it past " \
              "the number so the telling is true. (default: unmetered)"
      option :plan,
        aliases: ["--plans"],
        desc:    "Only these plans, comma separated: NNN or NNN.MM, e.g. --plan 003,005.01. Default: the whole tree"
      option :root, desc: "Repository root the agents work in (default: the .plans parent)"
      option :isolation,
        default: "worktree",
        values:  %w[worktree shared],
        desc:    "worktree: a checkout and branch per plan, run in parallel. shared: one tree, serial"
      option :jobs,
        aliases: ["-j"],
        desc:    "Agents to run at once (default: cores - 2, capped at 12)"
      option :git_push,
        type:    :boolean,
        default: true,
        desc:    "With --isolation worktree, a finished branch is pushed and its pull request " \
                 "opened as soon as it lands, titled [NNN.MM](X). --no-git-push turns that off and leaves it uncommitted."
      option :log, desc: "Append progress to this file (default: a per-project file under the system temp dir)"
      option :redis_url,
        desc: "Redis for the live board, its commands and plan claims shared with other machines " \
              "(default: .openlanes.yml redis_url, else $REDIS_URL, else #{Live::DEFAULT_URL})"
      option :web,
        type:    :boolean,
        default: true,
        desc:    "Serve the control room beside the run, when Redis answers; --no-web runs headless"
      option :open,
        type:    :boolean,
        default: true,
        desc:    "Open the control room in the browser; --no-open only prints its URL"
      option :port,
        default: OpenLanes::Web::DEFAULT_PORT.to_s,
        desc:    "Port the control room listens on, on 127.0.0.1"
      option :until_settled,
        type:    :boolean,
        default: false,
        desc:    "End at the first fixed point even with the control room up, as CI wants; " \
                 "without it the engine and the page stay up until Stop All Local or Ctrl-C"

      example [
        "-n                     # show which agent would take which plan",
        "                       # run them, one worktree per plan, in parallel",
        "-j 4                   # …with four at a time",
        "--isolation shared     # one tree, serial — no git required",
        "--rounds 3             # …capping every agent at three rounds per plan",
        "--plan 005,006,007     # only the plans a batch step just created",
        "--no-web               # headless: no control room, no browser; ends when the tree settles",
        "--until-settled        # with the control room, but ending when the tree settles"
      ]

      # Option precedence, quietest to loudest: the built-in default, then
      # `.openlanes.yml` (`jobs`, and the `commands.run` section), then the flag
      # actually typed. {Base.default_params} has already folded the file in.
      #
      # @param options [Hash]
      # @return [void]
      def call(**options)
        if options[:prompt] && !options[:agent]
          refuse("--prompt only works with --agent: it speaks to one agent, and without " \
                 "that restriction every agent in the round would hear it.",
            64)
        end

        tree   = tree_for(options)
        root   = options[:root] || File.dirname(tree.dir)
        agents = OpenLanes::Agents.registry
        agents = filtered(agents, options[:agent]) if options[:agent]
        agents = skipped(agents, options[:skip], options[:agent]) if options[:skip]
        plans  = options[:plan] ? scoped(tree, options[:plan]) : nil
        assignable!(agents, tree, plans, options[:agent]) if options[:agent]

        isolation = options.fetch(:isolation, "worktree").to_sym
        jobs      = (options[:jobs] || UI.default_jobs).to_i
        timeout   = options[:timeout]&.to_i

        if isolation == :worktree && !OpenLanes::Vcs.worktree(root:).repository?
          refuse("#{root} is not a git repository, so plans cannot be isolated.\n\n" \
                 "Run with --isolation shared to work in one tree, serially.",
            66)
        end

        # Set before the loop starts, not after: `UI.animate?` (and therefore
        # whether a round prints anything at all) is read the whole time the
        # loop runs, not just when `report` prints its closing summary.
        quiet?(options)
        UI.log_path = options[:log] ||
                      File.join(Dir.tmpdir, "openlanes-#{File.basename(root)}.log")
        info("Progress: #{UI.log_path}") unless quiet?(options)
        credentials_warning if !dry_run?(options) && !quiet?(options)
        spec_warning(tree, plans) unless quiet?(options)

        # The state file is what a harness that dies leaves for the next one.
        # It sits in .plans/ so a reboot keeps it, and it is ignored by name
        # so it never rides along in a commit. Editing somebody's .gitignore
        # is announced, the once it happens. The runner drops the file on a
        # dry run, which is why it can be built unconditionally.
        state = Engine.state_file(tree)
        if !dry_run?(options) && Engine::StateFile.ensure_ignored!(root) && !quiet?(options)
          info("Added #{Engine::StateFile::IGNORE.join(" and ")} to .gitignore: the run keeps its state there.")
        end

        # Control files from a previous run would otherwise be read as orders
        # to this one. Progress goes to STDERR as lines; the web view (plan 004)
        # is what will draw the board and take kill, extend and stop.
        Execution::Control.reset!

        live = live_for(root:, tree:, agents:, options:)
        web = web_for(live, root:, tree:, options:)
        runner = Engine.runner(
          tree:,
          agents:,
          isolation:,
          jobs:,
          plans:,
          state:,
          worktree:  (OpenLanes::Vcs.worktree(root:) if isolation == :worktree),
          rounds:    options[:rounds]&.to_i,
          executor:  Execution.executor(root:,
            timeout:,
            dry_run:      dry_run?(options),
            instructions: instructions_from(options[:prompt]),
            model:        options[:model],
            max_tokens:   options[:max_tokens]&.to_i,
            lean:         !options[:user_config]),
          dry_run:   dry_run?(options),
          publisher: publisher_for(root, isolation, options),
          on_board:  live&.on_board,
          claims:    live&.claims,
          **staying(options, web)
        )

        started  = UI.monotonic
        attempts = begin
          Execution.on_interrupt(signals:) { runner.call { |dispatcher| live&.attach(dispatcher) } }
        ensure
          live&.close
          web&.stop
        end
        finish(runner, attempts, options, seconds: UI.monotonic - started)
      end

      private

      # What the runner is told about idling past its fixed points. With its
      # control room up the engine stays, since the page can answer a blocked
      # plan or create the next one at any moment, and a run that had ended
      # would leave the page talking to nobody. Headless, or with
      # `--until-settled`, it ends at the first fixed point.
      #
      # @param options [Hash]
      # @param web [OpenLanes::Web::Launcher, nil] the control room, when it came up
      # @return [Hash] `stay:` and `rescan:` for {Engine::Runner}, or nothing
      def staying(options, web)
        return {} if web.nil? || options[:until_settled]

        info("The engine stays up with its control room: Stop All Local or Ctrl-C ends it.") unless quiet?(options)
        { stay: true, rescan: Engine::Dispatcher::RESCAN }
      end

      # Signals that stop the run gracefully, the way the first Ctrl-C does.
      # TERM too: a run with its control room stays up like a service, and a
      # service manager stops a service that way.
      #
      # @return [Array<String>]
      def signals = %w[INT TERM]

      # The closing report, and the exit status: 1 when any attempt failed.
      #
      # @param runner [OpenLanes::Engine::Runner]
      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @param options [Hash]
      # @param seconds [Float]
      # @return [void]
      def finish(runner, attempts, options, seconds:)
        report(runner, attempts, options, seconds:)
        exit(failures(attempts).empty? ? 0 : 1)
      end

      # Where the browser is sent once the control room answers.
      #
      # @param web [OpenLanes::Web::Launcher]
      # @param _tree [OpenLanes::Plans::Tree]
      # @return [String]
      def browser_url(web, _tree) = web.url

      # A live board this run cannot do without. `run` goes on headless, and
      # {Start}, whose page is its only way in, refuses instead.
      #
      # @param message [String] why there is no board
      # @param options [Hash]
      # @return [nil]
      def without_live(message, options)
        return nil if quiet?(options)

        warn("#{message}\n\nThe run goes on without the live board: no page, no commands from it, and no " \
             "plan claims shared with other machines. Start redis-server, or pass --redis-url.")
        nil
      end

      # @param web [OpenLanes::Web::Launcher] one that did not answer
      # @param _live [OpenLanes::Live::Session]
      # @param options [Hash]
      # @return [nil]
      def without_web(web, _live, options)
        return nil if quiet?(options)

        warn("The control room did not answer on #{web.url}, so the run goes on without it. Its log: #{web.log}")
        nil
      end

      # The live board (W6, W13, W26), when this run has one: not on a dry
      # run, which must leave nothing behind, and not without Redis, where
      # the run goes on exactly as it did before there was a page. Either
      # way it is said once, so a page that never updates is not a mystery.
      #
      # @param root [String]
      # @param tree [OpenLanes::Plans::Tree]
      # @param agents [OpenLanes::Agents::Registry]
      # @param options [Hash]
      # @param live [Boolean] false runs without Redis at all, for the
      #   headless flags a later command adds
      # @return [OpenLanes::Live::Session, nil]
      def live_for(root:, tree:, agents:, options:, live: true)
        return nil unless live

        if dry_run?(options)
          warn("Dry run: the live board is off, so nothing is published to Redis and no plan is claimed.") unless quiet?(options)
          return nil
        end

        config = Config.current
        store = Live.connect(Live.redis_url(option: options[:redis_url], config:))
        Live.session(store:, root:, tree:, agents:, project: config.project).tap do |session|
          info("Live board: #{session.describe}") unless quiet?(options)
        end
      rescue Live::Unavailable => e
        without_live(e.message, options)
      end

      # The control room (W1, W7): `openlanes web` as its own process beside
      # the engine, reading the board this run publishes. Only with a live
      # board to read, so a dry run, a run without Redis and `--no-web` all
      # stay headless. A server that does not come up is reported and left
      # out; the run is the agents' work, and the page is a view of it.
      #
      # @param live [OpenLanes::Live::Session, nil]
      # @param root [String]
      # @param tree [OpenLanes::Plans::Tree]
      # @param options [Hash]
      # @return [OpenLanes::Web::Launcher, nil] running, for the run to stop
      def web_for(live, root:, tree:, options:)
        return nil if live.nil? || options[:web] == false

        web = OpenLanes::Web.launcher(root:,
          plans_dir: tree.dir,
          port:      options[:port] || OpenLanes::Web::DEFAULT_PORT,
          redis_url: live.store.url).start
        unless web.ready?
          web.stop
          return without_web(web, live, options)
        end

        info("Control room: #{web.url}") unless quiet?(options)
        OpenLanes::Web.open(browser_url(web, tree)) unless options[:open] == false
        web
      end

      # The attempts list, padded into columns.
      #
      # Tabs used to separate these, which put every column on the next
      # multiple of eight: one agent's name a character longer than the
      # next one's pushed its round and mark a whole stop to the right, so
      # nothing under `luke-backend` and `yoda-writer` lined up. Widths come
      # from the rows themselves, so the columns are as narrow as the run
      # allows and still square.
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

      # `--prompt` takes the instructions themselves or a file holding them.
      # A short argument naming an existing file is read; anything else is
      # the text, so a sentence that happens to match a filename in the
      # project is not silently swapped for that file once it is long enough
      # to be a sentence.
      #
      # @param prompt [String, nil]
      # @return [String, nil]
      def instructions_from(prompt)
        return prompt unless prompt && prompt.length < PROMPT_PATH_LIMIT && File.file?(typed_path(prompt))

        File.read(typed_path(prompt))
      end

      # @param agents [OpenLanes::Agents::Registry]
      # @param name [String]
      # @return [OpenLanes::Agents::Registry] holding only the agent named — the
      #   restriction has to reach assignments, not just chaining, or a flag
      #   like `--prompt` aimed at one agent leaks to the whole round
      def filtered(agents, name)
        agents.find(name) or
          refuse("No agent called #{name}.\n\nKnown: #{agents.all.map(&:name).join(", ")}", 65)
        agents.only(name)
      end

      # Each name is checked against the full roster, not the possibly
      # already-restricted one, so `--skip` misspelled is a refusal rather
      # than a silent no-op — the same reasoning `--plan` applies to numbers.
      #
      # @param agents [OpenLanes::Agents::Registry]
      # @param text [String] comma-separated agent names
      # @param restricted [String, nil] what `--agent` asked for, if anything
      # @return [OpenLanes::Agents::Registry] without the agents named
      def skipped(agents, text, restricted)
        roster = OpenLanes::Agents.registry
        names  = text.split(",").map(&:strip).reject(&:empty?)
        names.each do |name|
          roster.find(name) or
            refuse("No agent called #{name}.\n\nKnown: #{roster.all.map(&:name).join(", ")}", 65)
          next unless name == restricted

          refuse("--agent #{name} and --skip #{name} contradict each other: " \
                 "one asks for only this agent, the other for anything but.",
            64)
        end
        agents.without(*names)
      end

      # A spec.md whose frontmatter does not parse routes as if it had none:
      # lane full, every override dropped. An eval agent's unquoted backtick
      # sent a quick-lane rename to research that way, and said nothing.
      # {Plans::Spec#problems} already knew; say it before agents are assigned.
      #
      # @param tree [OpenLanes::Plans::Tree]
      # @param plans [Array<OpenLanes::Plans::Ordinal>, nil] the --plan ordinals, nil for all
      # @return [void]
      def spec_warning(tree, plans)
        lines = tree.subjects.filter_map { |subject|
          ordinal = subject.feature.ordinal
          next if plans && !plans.include?(ordinal)

          problems = Plans::Spec.for(subject).problems
          "#{ordinal}: #{problems.join("; ")}" unless problems.empty?
        }
        return if lines.empty?

        warn("spec.md frontmatter ignored in part, so these plans route on defaults:\n" \
             "#{lines.join("\n")}")
      end

      # `--plan` names the whole point of scoping: a skill that just minted
      # N folders hands off exactly those, not the tree. A typo'd or already-
      # settled number silently running the whole tree instead is the failure
      # this exists to prevent, so an unknown one is refused rather than
      # dropped.
      #
      # @param tree [OpenLanes::Plans::Tree]
      # @param text [String]
      # @return [Array<OpenLanes::Plans::Ordinal>]
      def scoped(tree, text)
        known = tree.subjects.map { |s| s.feature.ordinal }
        text.split(",").map(&:strip).reject(&:empty?).map { |token|
          ordinal = Plans::Ordinal.parse(token)
          unless ordinal && known.include?(ordinal)
            refuse("No plan #{token} in #{tree.dir}.\n\n" \
                   "Known: #{known.join(", ")}",
              66)
          end
          ordinal
        }
      end

      # `--agent` narrowing the round to nobody used to exit 0 in silence —
      # "0 plans addressed", green box, no hint that the agent named simply
      # does not handle any in-scope plan's state. Someone who typed both an
      # agent and a plan meant them to meet, so a pairing that cannot happen
      # is refused up front with the agent that would actually take each plan.
      #
      # @param agents [OpenLanes::Agents::Registry] already narrowed to the one agent
      # @param tree [OpenLanes::Plans::Tree]
      # @param plans [Array<OpenLanes::Plans::Ordinal>, nil]
      # @param name [String]
      # @return [void]
      def assignable!(agents, tree, plans, name)
        agent  = agents.find(name)
        active = tree.subjects.select { |s|
          (plans.nil? || plans.include?(s.feature.ordinal)) &&
            !Plans::StateMachine::SETTLED.include?(s.status.key)
        }
        return if active.empty? || active.any? { |s| agent.handles?(s.status) }

        roster  = OpenLanes::Agents.registry
        lines   = active.map { |s|
          takers = OpenLanes::Agents::Routing.filter(roster.for_status(s.status), s).map(&:name)
          verb   = takers.size == 1 ? "takes" : "take"
          "  #{s.feature.ordinal} is #{s.status.emoji} #{s.status.label}" \
            "#{" - #{takers.join(" and ")} #{verb} it" unless takers.empty?}"
        }
        handled = agent.handles.map { |k| OpenLanes::Plans::STATUS_BY_KEY[k]&.then { |st| "#{st.emoji} #{st.label}" } || k }
        refuse("#{name} handles #{handled.join(", ")}, and no plan in scope is there:\n\n" \
               "#{lines.join("\n")}\n\nName the agent that takes these states, or drop --agent.",
          65)
      end

      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @return [Array<OpenLanes::Engine::Runner::Attempt>]
      def failures(attempts) = attempts.reject(&:ok)

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
      # @param options [Hash]
      # @return [OpenLanes::Vcs::Publisher, nil]
      def publisher_for(root, isolation, options)
        if isolation != :worktree || options[:git_push] == false
          unless quiet?(options)
            warn("No pull request will be opened (#{isolation == :worktree ? "--no-git-push" : "--isolation shared"}), " \
                 "so a finished build stays at 🟡 Building:\n🟢 Ready for Review needs an open pull request, and hansolo-reviewer reviews one.")
          end
          return nil
        end

        Vcs.publisher(root:, dry_run: dry_run?(options))
      end

      # One line per attempt: the plan, who ran, which of that agent's rounds
      # it was, what moved, and the note. There is no round header any more
      # because the loop has no rounds of its own: each agent counts its own
      # per plan, so two agents on one plan can be on different numbers.
      #
      # @param runner [OpenLanes::Engine::Runner]
      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @param options [Hash]
      # @param seconds [Float] wall clock for the whole loop
      # @return [void]
      def report(runner, attempts, options, seconds: 0.0)
        # A leading blank line, because the spinners this replaces write to
        # STDERR and the last of them may have left the cursor mid-line:
        # without it the first attempt starts wherever that line stopped,
        # indented by however much it had drawn.
        puts ""
        puts attempt_lines(attempts)

        # What the run cost, on STDOUT with the attempts it belongs to, so a run
        # redirected to a file keeps its bill. A dry run spent nothing and gets
        # none of this.
        tally = Engine.tally(attempts:, seconds:)
        puts("", tally.render) unless dry_run?(options)

        return if quiet?(options)

        if Execution::Control.quit?
          warn("Stopped from the keyboard — q. Unfinished plans keep their state; " \
               "re-run to resume where they stand.")
        end

        advanced = attempts.count(&:advanced?)
        blocked  = runner.blocked
        summary  = ["#{attempts.size} invocation#{"s" unless attempts.size == 1}", "#{advanced} advanced"]
        summary << (runner.isolated? ? "#{runner.jobs} at a time, one worktree each" : "serial, shared tree")
        summary << "#{blocked.size} blocked" unless blocked.empty?
        summary << "#{failures(attempts).size} failed" unless failures(attempts).empty?

        if dry_run?(options)
          warn("Dry run — no agent was invoked.\n#{summary.join(" · ")}\n\nRe-run without --dry-run.")
        elsif failures(attempts).empty?
          success("#{summary.join(" · ")}#{"\n\nEvery plan is done or deliberately parked." if runner.settled?}")
        else
          error("#{summary.join(" · ")}\n\n#{failures(attempts).map { |f| "#{f.ordinal} #{f.agent}: #{f.note}" }.join("\n")}")
        end

        return if blocked.empty?

        warn("#{blocked.size} plan#{"s" unless blocked.size == 1} need a human decision:\n" +
               blocked.map { |b| "  #{b.feature.ordinal} #{b.status.emoji} #{b.feature.title} — see blocked.md" }.join("\n") +
               "\n\nWrite the answers into blocked.md, then: openlanes unblock " \
               "#{blocked.map { |b| b.feature.ordinal }.join(",")}")
      end
    end
  end
end
