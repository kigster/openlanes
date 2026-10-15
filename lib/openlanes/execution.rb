# frozen_string_literal: true

module OpenLanes
  # One agent invocation: the child process, its clock, the control file it
  # polls, and the transcript it streams back. The autonomy boundary lives
  # here, because this is the only place a coding agent is started.
  module Execution
    module_function

    # @return [OpenLanes::Execution::Executor]
    def executor(**) = Executor.new(**)

    # Run the block with Ctrl-C turned into a cooperative interrupt.
    #
    # @param signals [Array<String>] handled as Ctrl-C is
    # @return [Object] whatever the block returns
    def on_interrupt(signals: %w[INT], &) = Control.on_interrupt(signals, &)

    # `claude` prefers a credential in the environment to a claude.ai login,
    # so a project `.env` that direnv loads on `cd` can redirect every agent
    # a run spawns to a key meant for the application itself.
    #
    # Said once, before agents start, because the failure arrives three
    # minutes later, once per agent, and reads like an agent problem rather
    # than an environment one. Words only: a command or a workflow draws it.
    #
    # @return [String, nil] the warning, or nil when no credential shadows the login
    def credentials_notice
      names = Executor.foreign_credentials
      return if names.empty?

      one = names.size == 1
      "#{names.join(" and ")} #{one ? "is" : "are"} set in this shell, so every agent authenticates " \
        "with #{one ? "it" : "them"} rather than with your claude.ai login.\n" \
        "A stale one fails every agent in the run with `401 API key is invalid`, " \
        "three minutes at a time.\n" \
        "If it came from a project .env, run `unset #{names.join(" ")}` first."
    end
  end
end
