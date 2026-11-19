# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What a {Agents::Agent#confined? confined} agent may touch: its own
      # files through Edit, a few commands that neither execute nor write,
      # and its ledger. Everything else is taken away.
      module Confinement
        # The whole tool set of a {Agents::Agent#confined? confined} agent.
        # `--tools` takes every other tool away and `dontAsk` refuses whatever
        # the allow list below does not name, so Edit reaches only its files
        # and Bash only these commands: a prompt that says "only spec.md" is a
        # request, this is the check.
        CONFINED_TOOLS = %w[Read Grep Glob Edit Bash].freeze

        # The commands a confined agent may run besides this checkout's own
        # `openlanes state`, which signs its ledger. A grant is `Bash(cmd:*)`,
        # so every flag of a listed command is reachable: `rg --pre` runs any
        # program and `git log|show|diff --output=` writes any file, which is
        # how the first version of this list escaped its own confinement. Only
        # commands with no flag that executes or writes belong here; Read, Grep
        # and Glob cover the rest.
        CONFINED_COMMANDS = ["ls", "git status"].freeze

        # The one `openlanes` subcommand a confined agent may run: `state`
        # shows and signs its ledger. The whole executable would hand it
        # `run` and `resync`, which rename folders.
        CONFINED_CLI = "#{Prompt::EXECUTABLE} state".freeze

        module_function

        # What this agent may use on this plan: its own `allowed_tools`, or for
        # a confined agent Edit on its files and nothing else that writes. The
        # leading `/` makes the rule absolute (`//Users/...`); one slash alone
        # is read relative to the settings file.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Array<String>]
        def allowed_for(agent, subject)
          return agent.allowed_tools unless agent.confined?

          edits = agent.confined_to.map { "Edit(/#{File.expand_path(it, subject.feature.path)})" }
          commands = [CONFINED_CLI, *CONFINED_COMMANDS].map { "Bash(#{it}:*)" }
          %w[Read Grep Glob] + edits + commands
        end
      end
    end
  end
end
