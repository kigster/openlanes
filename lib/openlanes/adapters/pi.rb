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
        confines: false,
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

      # Pi has no sandbox, so it gets no tools to need one.
      #
      # @param prompt [String]
      # @param model [String, nil]
      # @return [Array<String>]
      def question_argv(prompt, model: nil)
        ["pi", "--print", "--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-prompt-templates",
         *(model ? ["--model", model] : []), prompt]
      end

      private

      # `pi --list-models` exits 0 either way: with no provider signed in it
      # prints a sentence instead of its table. A model is `provider/id`,
      # the form `--model` accepts.
      #
      # @param runner [OpenLanes::Adapters::ProbeRunner]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def check(runner, at)
        result = runner.call("pi", "--list-models")
        return timed_out(result, at) if result.timed_out?

        models = listed(result.stdout)
        return Availability.down(name, "no model provider signed in (run `pi`, then `/login`)", at) if models.empty?

        Availability.up(name, models, at)
      end

      # @param table [String] a header row starting `provider`, then one row per model
      # @return [Array<OpenLanes::Adapters::Model>]
      def listed(table)
        lines = table.lines.map(&:split)
        start = lines.index { it.first == "provider" } or return []
        lines.drop(start + 1).filter_map do |(provider, model)|
          next unless provider && model

          id = "#{provider}/#{model}"
          Model.new(id:, label: id)
        end
      end
    end
  end
end
