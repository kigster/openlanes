# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The defaults of {Options} that are not nil. A lambda is called per
      # executor, so no two share a throttle.
      OPTION_DEFAULTS = {
        dry_run: false, lean: true, fresh_budget: false, memory: true,
        usable: -> { Agents::Dealing::ANY }, trace_dir: -> { TRACE_DIR }, throttle: -> { Throttle::Backoff.new }
      }.freeze

      # The keywords {Executor#initialize} takes, with their defaults, in
      # one value. The root is expanded and the instructions stripped, as the
      # executor reads them.
      #
      # @!attribute [r] root [String] the repository the agents work in
      # @!attribute [r] spawn [#call, nil] `argv, chdir:, env:, label:` → an {AgentProcess}, or
      #   anything with its interface, so the suite can play back a fake process
      #   without spawning one; nil runs each agent under `openlanes-agent` (S6)
      # @!attribute [r] timeout [Integer, nil] `--timeout`: a cap on every agent's clock,
      #   or nil to let each agent's own frontmatter clock stand
      # @!attribute [r] dry_run [Boolean] plan the invocation, do not run it
      # @!attribute [r] trace_dir [String] where each invocation's raw stream is kept
      # @!attribute [r] instructions [String, nil] what `run --prompt` typed, appended
      #   to the agent's own prompt. The command only accepts it alongside
      #   `--agent`, so exactly one agent ever hears it.
      # @!attribute [r] model [String, nil] what `run --model` typed. The flag actually
      #   typed beats what an agent's frontmatter declares, the same precedence
      #   every other flag here follows; nil leaves each agent its own choice.
      # @!attribute [r] max_tokens [Integer, nil] budget per invocation, input plus
      #   output, sub-agents included. The prompt states it so the agent can
      #   plan to finish inside it, and the meter enforces it so the statement
      #   is true. nil is unmetered.
      # @!attribute [r] fresh_budget [Boolean] count only new tokens against
      #   +max_tokens+, leaving out cache reads; what `eval --live` uses
      # @!attribute [r] lean [Boolean] start agents without the operator's personal
      #   plugins, skills, hooks and MCP servers; `run --user-config` turns it off
      # @!attribute [r] usable [#call] adapter name → whether the startup probe left it
      #   usable, so a reviewer is never dealt a signed-out CLI (plan 031, D12)
      # @!attribute [r] packets [#call, nil] plan → the review packet its reviewers
      #   open with ({ReviewPacket}); nil, the default, sends reviewers to the
      #   documents and `gh pr diff` themselves, so nothing that builds an
      #   executor without asking for packets reaches GitHub
      # @!attribute [r] memory [Boolean] tell each agent the project's lessons for it;
      #   `run --no-memory` turns it off, the baseline that says whether they help.
      #   The lessons are read once, at the first invocation, and kept for the run
      # @!attribute [r] throttle [OpenLanes::Execution::Throttle::Backoff] how long an
      #   agent waits out a provider's rate limit or overload, and when it
      #   stops waiting; the suite hands in one that does not sleep
      Options = Data.define(:root,
        :spawn,
        :timeout,
        :dry_run,
        :trace_dir,
        :instructions,
        :model,
        :max_tokens,
        :lean,
        :fresh_budget,
        :usable,
        :packets,
        :memory,
        :throttle) do
        def initialize(root:, **given)
          nils = self.class.members.to_h { [it, nil] }
          defaults = OPTION_DEFAULTS.transform_values { it.respond_to?(:call) ? it.call : it }
          super(**nils, **defaults, **given, root: File.expand_path(root), instructions: given[:instructions].to_s.strip)
        end
      end
    end
  end
end
