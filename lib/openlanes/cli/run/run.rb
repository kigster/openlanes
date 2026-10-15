# frozen_string_literal: true

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

      # @param options [Hash]
      # @return [void]
      def call(**options)
        tree = tree_for(options)
        exit(unwrap(workflow(tree, options.merge(quiet: quiet?(options))).call))
      end

      private

      # @param tree [OpenLanes::Plans::Tree]
      # @param options [Hash]
      # @return [OpenLanes::Engine::RunWorkflow]
      def workflow(tree, options) = Engine.run(tree:, origin:, **options)
    end
  end
end
