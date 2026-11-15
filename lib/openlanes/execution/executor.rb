# frozen_string_literal: true

module OpenLanes
  module Execution
    # Runs one agent against one plan by shelling out to a coding agent CLI:
    # `claude` unless the agent's definition or the plan's spec.md names
    # another {OpenLanes::Adapters adapter}.
    #
    # The autonomy boundary, "docs plus code, but nothing leaves the machine",
    # is enforced twice over. Before, the agent is told, and {Grants} withholds
    # the tools that would let it push. After, {Boundary} checks that HEAD did
    # not move and that no remote-tracking ref was moved by a push. A prompt
    # is a request; a check is a guarantee, and only one of them survives a
    # model deciding it knows better.
    class Executor
      include Choices
      include Permissions
      include Reporting
      extend Shortcuts

      # The names callers and agent documentation use, each documented at its source.
      DENIED_TOOLS = Grants::DENIED_TOOLS
      FORBIDDEN_COMMANDS = Grants::FORBIDDEN_COMMANDS
      UNGRANTABLE = Grants::UNGRANTABLE
      TRACE_DIR = Traces::DIR
      CREDENTIAL_VARS = Credentials::VARS
      REASON_LIMIT = Said::LIMIT
      DEFAULT_TIMEOUT = Preferences::DEFAULT_TIMEOUT
      AUTH_FAILURE = AuthFailure::PATTERN

      # @param options [Hash] the keywords {Options} takes, each documented there
      def initialize(**)
        options = Options.new(**)
        @root = options.root
        @dry_run = options.dry_run
        @model = options.model
        @preferences = Preferences.new(model: @model, timeout: options.timeout, usable: options.usable)
        @invocations = Invocation.new(lean: options.lean, trace_dir: options.trace_dir, prompts: PromptAssembly.new(options, @preferences))
        crew = Crew.build(options, @preferences, @invocations)
        @verdict = crew.verdict
        @first_start = FirstStart.new(crew)
        @retake = Retake.new(crew)
      end

      # @return [String] the checkout; [String, nil] what `run --model` typed
      attr_reader :root, :model

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param handle [OpenLanes::Execution::Executor::Handle, nil] filled in for the caller
      # @param asked [Hash] the keywords {Request} takes, each documented there
      # @return [OpenLanes::Execution::Executor::Result]
      # @yieldparam progress [OpenLanes::Execution::Transcript::Progress]
      def call(agent, subject, handle: nil, **asked, &)
        started = UI.monotonic
        return Refusal.dry_run(agent) if @dry_run

        request = Request.new(root: @root, **asked)
        attempt = attempt_for(agent, subject, request.root, handle || Handle.new)
        refused = Refusal.unconfinable(agent, attempt.profile)
        return refused if refused

        @first_start.call(attempt.with(trace: @invocations.trace_path(agent, subject)), request, started, &)
      end

      # Take back an agent an earlier engine started and did not see end ({Retake}).
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param restart [Hash{String => Object}] the state file's record of {Handle#restart!}
      # @param handle [OpenLanes::Execution::Executor::Handle]
      # @return [OpenLanes::Execution::Executor::Result]
      # @yieldparam progress [OpenLanes::Execution::Transcript::Progress]
      def reattach(agent, subject, restart:, handle: Handle.new, &)
        started = UI.monotonic
        attempt = attempt_for(agent, subject, restart.fetch("cwd"), handle)
        @retake.call(attempt.with(trace: restart.fetch("trace")), restart, started, &)
      end

      # The exact argv {#call} would start, so a spec can assert the boundary
      # flags without running anything.
      # @param asked [Hash] the {Request}, as {#call} takes it, plus `control:`
      # @return [Array<String>]
      def invocation(agent, subject, **asked)
        request = Request.new(root: @root, **asked)
        @invocations.first(attempt_for(agent, subject, request.root, nil), request)
      end

      private

      # @return [OpenLanes::Execution::Executor::Attempt] not yet started, and with no trace yet
      def attempt_for(agent, subject, root, handle)
        Attempt.new(agent:, subject:, root:, profile: profile_for(agent, subject, root:), trace: nil, handle:, sessions: Sessions.new)
      end
    end
  end
end
