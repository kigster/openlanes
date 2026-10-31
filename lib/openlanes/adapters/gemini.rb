# frozen_string_literal: true

require "securerandom"

module OpenLanes
  module Adapters
    # `gemini -p`, streaming JSON (gemini CLI 0.51.0).
    #
    # Built from the CLI's bundled source rather than a recorded run: the
    # account this was written on is refused (`IneligibleTierError`). Gemini
    # refuses denied commands through its policy engine ({Policy}), resumes
    # a session by id, and has no effort flag, so effort is not passed.
    class Gemini < Base
      # `-r <id>` carries a session on. `/compress` exists, but under `-p` it
      # starts in the background and the words `/compress` go to the model as
      # a prompt, so nothing compacts. Its policy refuses named commands, not
      # everything outside an agent's own files, so a confined agent is not
      # run on it.
      CAPABILITIES = Capabilities.new(compacts: false,
        resumes: true,
        enforces_tool_denial: true,
        confines: false,
        compact_prompt: nil)

      # The models gemini 0.51.0 knows by name, most capable first. It has no
      # command that lists them, and nobody has priced them here.
      MODELS = %w[gemini-3.1-pro-preview gemini-3-pro-preview gemini-2.5-pro
                  gemini-3.5-flash gemini-3-flash-preview gemini-2.5-flash gemini-3.1-flash-lite]
               .map { Model.new(id: it, label: it) }.freeze

      # Exit status of a run with no auth method configured.
      SIGNED_OUT = 41

      # Exit status of the probe's empty prompt once sign-in has been checked.
      NO_INPUT = 42

      # What gemini prints on stderr when the account cannot use this client.
      REFUSED = /IneligibleTierError: ([^\n.]*)/

      # What it prints when signing in failed for any other reason.
      AUTH_FAILED = /Error authenticating: ([^\n]*)/

      # @return [OpenLanes::Adapters::Capabilities]
      def capabilities = CAPABILITIES

      # @return [Array<OpenLanes::Adapters::Model>]
      def models = MODELS

      # @param invocation [OpenLanes::Adapters::Invocation]
      # @return [Array<String>]
      def argv(invocation)
        policy = Policy.new(denied_commands: invocation.denied_commands, network: invocation.network)
        argv = ["gemini", *session(invocation), "-p", invocation.prompt,
                "-o", "stream-json", "--skip-trust", "--approval-mode", "yolo", "--policy", policy.path]
        argv += ["-m", invocation.model] if invocation.model
        argv
      end

      # Plan mode, which cannot edit or run anything.
      #
      # @param prompt [String]
      # @param model [String, nil]
      # @return [Array<String>]
      def question_argv(prompt, model: nil)
        ["gemini", "-p", prompt, "--approval-mode", "plan", "--skip-trust", "-o", "text", *(model ? ["-m", model] : [])]
      end

      # Thinking is a settings key, not a flag.
      #
      # @return [nil]
      def effort(_effort) = nil

      # @param trace [String, nil]
      # @return [OpenLanes::Adapters::Gemini::Stream]
      def transcript(trace: nil, **, &) = Stream.new(trace:, &)

      private

      # `--session-id` names a new session and `-r` resumes one; gemini
      # refuses the two together.
      #
      # @param invocation [OpenLanes::Adapters::Invocation]
      # @return [Array<String>]
      def session(invocation) = invocation.resume ? ["-r", invocation.resume] : ["--session-id", SecureRandom.uuid]

      # An empty prompt with stdin closed: gemini checks the sign-in, then
      # exits for want of input without calling a model. Signed out is exit
      # 41; a refused account still exits 42 and says so only on stderr.
      #
      # @param runner [OpenLanes::Adapters::ProbeRunner]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def check(runner, at)
        result = runner.call("gemini", "-p", "", "--skip-trust")
        return timed_out(result, at) if result.timed_out?

        reason = refusal(result)
        reason ? Availability.down(name, reason, at) : Availability.up(name, models, at)
      end

      # @param result [OpenLanes::Adapters::ProbeRunner::Result]
      # @return [String, nil] why gemini cannot take an agent, nil when it can
      def refusal(result)
        return "not signed in (run `gemini` and choose a sign-in method)" if result.status == SIGNED_OUT
        return "account tier refused: #{result.stderr[REFUSED, 1]}" if result.stderr.match?(REFUSED)
        return "sign-in failed: #{result.stderr[AUTH_FAILED, 1]}" if result.stderr.match?(AUTH_FAILED)
        return nil if result.status == NO_INPUT

        "`gemini` exited #{result.status}: #{result.stderr.lines.last.to_s.strip}"
      end
    end
  end
end
