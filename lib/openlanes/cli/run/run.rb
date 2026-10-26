# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes run 005,006` — drive the specialist agents over the plans
    # named, headless, until nothing changes (C4). Every plan is claimed
    # before any agent starts and held until the run ends (O1), and a plan
    # the factory or another run holds refuses the whole command (O2).
    # `openlanes start` is the factory, with its control room, over the
    # whole tree.
    class Run < Base
      desc "Run specialist agents over the plans named, headless, until nothing changes"

      argument :plans,
        required: true,
        desc:     "The plans to work, comma separated: NNN or NNN.MM, e.g. 003,005.01"

      dry_run_option "Invoke no agent; print which agent would take which plan"
      option :rounds,
        desc: "Cap on rounds per agent per plan; each agent declares its own, at most 5 " \
              "(default: the agent's own)"
      option :timeout,
        desc: "Seconds before one agent is abandoned; only tightens an agent's own clock " \
              "(default: the agent's own, else 900)"
      option :agent, desc: "Only run this one agent"
      option :prompt,
        desc: "Extra instructions appended to the agent's prompt (only with --agent); " \
              "a path to an existing text file under #{Engine::RunWorkflow::PROMPT_PATH_LIMIT} characters is read instead"
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
      log_options
      option :redis_url,
        desc: "Redis for the live board, its commands and plan claims shared with other machines " \
              "(default: .openlanes.yml redis_url, else $REDIS_URL, else #{Live::DEFAULT_URL})"
      option :ignore_bombs,
        type:    :boolean,
        default: false,
        desc:    "Work on while a 💣 stands: a plan others wait on, blocked too long, halts nothing this run"
      option :until,
        desc: "Stop each plan once it reaches this state, by key or emoji (e.g. planned, 🔨): " \
              "short dogfood runs. Default: as far as the agents take it"

      example [
        "005 -n                 # show which agent would take plan 005",
        "005,006,007            # run them, one worktree per plan, in parallel",
        "005,006 -j 1           # …one at a time",
        "005 --isolation shared # one tree, serial — no git required",
        "005 --rounds 3         # …capping every agent at three rounds",
        "050 --until planned    # stop plan 050 once it is planned",
        "005 --ignore-bombs     # keep working while a 💣 stands"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        tree = tree_for(options)
        prepared = prepare(options.merge(quiet: quiet?(options)))
        registered(prepared) { |hooks| exit(unwrap(workflow(tree, prepared.merge(hooks)).call)) }
      end

      private

      # This process's PID file and title (S2, S5) for as long as the block
      # runs, and the pipe from a supervisor watched, when there is one. A
      # dry run starts no agent, so it names nothing.
      #
      # @param options [Hash]
      # @yieldparam hooks [Hash] what the workflow is handed: its `on_board`
      # @return [void]
      def registered(options)
        return yield({}) if dry_run?(options)

        Supervision.watch_lifeline
        plans = registered_plans(options)
        registration = Supervision.registration(role, root: Dir.pwd, plans:)
        unwrap(registration.claim)
        registration.title(plans.join(",")) unless plans.empty?
        registration.hold { yield({ on_board: on_board(registration) }.compact) }
      end

      # @return [String] the name in this process's title and PID file
      def role = Supervision::RUN

      # @param options [Hash]
      # @return [Array<String>] the plans named, for `openlanes status`
      def registered_plans(options) = options[:plan].to_s.split(",").map(&:strip).reject(&:empty?)

      # A run's title is its plans, set once.
      #
      # @param _registration [OpenLanes::Supervision::Registration]
      # @return [nil]
      def on_board(_registration) = nil

      # The plans argument, under the name the workflow reads.
      #
      # @param options [Hash]
      # @return [Hash]
      def prepare(options) = options.except(:plans).merge(plan: options[:plans])

      # @param tree [OpenLanes::Plans::Tree]
      # @param options [Hash]
      # @return [OpenLanes::Engine::RunWorkflow]
      def workflow(tree, options) = Engine.run(tree:, origin:, **options)
    end
  end
end
