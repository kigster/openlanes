# frozen_string_literal: true

module OpenLanes
  module Adapters
    # `pi -p --mode json`. Pi has no sandbox and no per-command denylist, so
    # the after-check is the only guard, and the prompt says as much.
    class Pi < Base
      # Pi's `--thinking` scale already uses these words.
      THINKING = Adapters::EFFORTS

      # `--no-session` every time: nothing resumes, nothing compacts, and
      # nothing refuses a denied tool but the after-check.
      CAPABILITIES = Capabilities.new(compacts: false,
        resumes: false,
        enforces_tool_denial: false,
        compact_prompt: nil)

      # @return [OpenLanes::Adapters::Capabilities]
      def capabilities = CAPABILITIES

      # @param invocation [OpenLanes::Adapters::Invocation]
      # @return [Array<String>]
      def argv(invocation)
        argv = ["pi", "--print", "--mode", "json", "--no-session"]
        argv += ["--no-extensions", "--no-skills", "--no-prompt-templates"] if invocation.lean
        argv += ["--model", invocation.model] if invocation.model
        argv += ["--thinking", invocation.effort] if THINKING.include?(invocation.effort.to_s)
        argv << invocation.prompt
      end
    end
  end
end
