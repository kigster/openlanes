# frozen_string_literal: true

require "dry/cli/autocomplete/command"
require "tty-screen"

# One file per command, `subcommands/` under the prefixed ones. Base carries
# the shared flags and plumbing, so it loads first; the rest only meet each
# other here, at registration.
require_relative "cli/base"
require_relative "cli/coverage/coverage"
require_relative "cli/create/create"
require_relative "cli/index/index"
require_relative "cli/init/init"
require_relative "cli/list_plans/list_plans"
require_relative "cli/resync/subcommands/dirs"
require_relative "cli/resync/subcommands/prs"
require_relative "cli/linear/linear"
require_relative "cli/linear/subcommands/projects"
require_relative "cli/linear/subcommands/import"
require_relative "cli/docs/docs"
require_relative "cli/eval/eval"
require_relative "cli/run/run"
require_relative "cli/setup/setup"
require_relative "cli/start/start"
require_relative "cli/unblock/unblock"
require_relative "cli/version/version"
require_relative "cli/web/web"
require_relative "cli/states/states"
require_relative "cli/uml/uml"
require_relative "cli/agents/subcommands/list"
require_relative "cli/agents/subcommands/describe"
require_relative "cli/worktree/worktree"
require_relative "cli/mail/mail"
require_relative "cli/mail/subcommands/send"
require_relative "cli/mail/subcommands/read"
require_relative "cli/mail/subcommands/ack"
require_relative "cli/mail/subcommands/render"
require_relative "cli/events/events"
require_relative "cli/events/subcommands/report"
require_relative "cli/state/state"
require_relative "cli/state/subcommands/sign"
require_relative "cli/state/subcommands/show"
require_relative "cli/state/subcommands/resume"
require_relative "cli/skills/subcommands/install"
require_relative "cli/api/api"
require_relative "cli/api/subcommands/docs"
require_relative "cli/preview/preview"
require_relative "cli/preview/subcommands/start"
require_relative "cli/preview/subcommands/status"
require_relative "cli/preview/subcommands/stop"

module OpenLanes
  # The command line. Every command is a thin shell over one library class:
  # it parses flags, calls one object, and prints the result.
  #
  # Two conventions hold throughout:
  #
  #   * The deliverable goes to STDOUT, progress and boxes go to STDERR, so
  #     every command composes in a pipe.
  #   * A command does the work it is named for, and `-n` / `--dry-run`
  #     previews it. Every change is reported as it is made: folder names and
  #     pull request titles are joined on by branches, `pull-requests.md` and
  #     merged history, and changing one silently is how a plan ends up filed
  #     under work it did not do.
  module CLI
    extend Dry::CLI::Registry

    # What `openlanes -h` prints above and below the command list. Rendering,
    # wrapping and colour belong to dry-cli-help; only the words live here.
    # dry-cli-help 0.2 configures once per process, not per registry, which
    # suits a gem with exactly one registry.
    Dry::CLI::Help.configure do
      title "Open Lanes Depot — Agentic Specification-Driven Development v#{OpenLanes::VERSION}"

      description <<~TEXT
        Drives the agentic flow: spec → plan → build → review → tune/fix → approve.

        Most days need two commands. `openlanes init` sets a project up, once.
        `openlanes start` is `web` + `run` in one: the engine and its control room
        in the browser, where you create plans, answer the agents' questions and
        watch them work. Both stay up, with or without plans, until Stop All Local
        in the page or Ctrl-C. The headless commands do the same work from the
        terminal, for scripts and CI.

        Keeps the .plans folders in step with GitHub pull requests and Linear issues.
        The final merge and deploy stay manual.
      TEXT

      epilogue <<~TEXT.chomp
        Global flags: -C, --no-color disables colour in every command.

        Documentation: https://github.com/kigster/openlanes
      TEXT

      # The bare program prints this screen, and asking for help is not a failure.
      exit_code_without_arguments 0

      # Wrap at column 90, or two short of the terminal when it is narrower.
      width [90, TTY::Screen.width - 2].min

      # Most used first: what a person types every day, then what scripts do.
      group "OpenLanes Default Web Operation", "setup", "init", "start"
      group "Headless Operation",
        "create",
        "run",
        "plans",
        "index",
        "resync",
        "unblock",
        "review",
        "worktree",
        "coverage",
        "project",
        "agents",
        "describe",
        "mail",
        "events",
        "state",
        "eval"
      group "Reference", "docs", "api", "states", "uml", "linear", "skills", "completion", "version"
    end

    register "setup", Setup
    register "init", Init
    register "create", Create, aliases: %w[new c]
    # `status` is the factory's (C1 in docs/decisions/decisions-on-factory-start-stop.md);
    # the plan table is `plans`, with no old spellings kept: nothing outside
    # this repository calls openlanes.
    register "plans", ListPlans
    register "run", Run
    register "start", Start
    # Spawned by `start`, not run by hand (C5): a page served on its own is
    # how a control room came to outlive its engine.
    register "web", Web, hidden: true
    register "unblock", Unblock
    register "review", Review
    register "eval", Eval
    register "worktree", Worktree
    # Beside the command, not instead of it: dry-cli runs `worktree 002` as
    # before, since "002" names no subcommand.
    register "worktree prune", WorktreePrune
    register "coverage", Coverage
    register "docs", Docs
    register "states", States, aliases: %w[diagram]
    register "uml", Uml
    register "index", Index, aliases: %w[idx]
    register "version", Version, aliases: %w[--version -v]

    register "agents" do |prefix|
      prefix.register "list", Agents::List, aliases: %w[ls]
      prefix.register "describe", Agents::Describe, aliases: %w[show]
    end

    # `describe <name>` without the `agents` in front of it. The bare verb is
    # how people ask for this out loud, and a near miss that prints usage is a
    # worse answer than the thing they wanted.
    register "describe", Agents::Describe

    register "resync" do |prefix|
      prefix.register "dirs", Resync::Dirs
      prefix.register "prs", Resync::Prs
    end

    register "linear" do |prefix|
      prefix.register "import", Linear::Import
      prefix.register "projects", Linear::Projects
    end

    # What a paired agent shells out to between steps. See {OpenLanes::Plans::Mailbox}.
    register "mail" do |prefix|
      prefix.register "send", Mail::Send
      prefix.register "read", Mail::Read
      prefix.register "ack", Mail::Ack
      prefix.register "render", Mail::Render
    end

    # The durable run log, read back. See {OpenLanes::Events}.
    register "events" do |prefix|
      prefix.register "report", Events::Report
    end

    # What every agent shells out to at the start and end of its round. See
    # {OpenLanes::Plans::PlanState}.
    register "state" do |prefix|
      prefix.register "sign", State::Sign
      prefix.register "show", State::Show
      prefix.register "resume", State::Resume
    end

    # Copies the skills bundled with the gem; see {OpenLanes::Skills}.
    register "skills" do |prefix|
      prefix.register "install", Skills::Install
    end

    # Lists and checks the OpenAPI contracts plans carry; see {OpenLanes::Presentation::ApiDocs}.
    register "api" do |prefix|
      prefix.register "docs", API::Docs
    end

    # The project being built, for the Preview tab (C2); see {OpenLanes::Apps}.
    register "project", aliases: %w[preview] do |prefix|
      prefix.register "start", Preview::Start
      prefix.register "status", Preview::Status
      prefix.register "stop", Preview::Stop
    end

    register "completion", ::Dry::CLI::Autocomplete::Command[::OpenLanes::CLI]
  end
end
