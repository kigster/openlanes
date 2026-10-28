# frozen_string_literal: true

module OpenLanes
  module Agents
    # Every agent's name, written once. Code names an agent only through one
    # of these, never as a string: the Star Wars names were spelled out in a
    # dozen places, and renaming them (decision N2 in
    # docs/decisions/decisions-on-agent-names-models-and-reviewers.md) meant
    # hunting every one down. A rename is now this file, the agent's
    # `agents/*.md`, and prose.
    #
    # `agents/*.md` stays the source of truth for what an agent does; a spec
    # holds the two lists to each other.
    module Names
      RESEARCHER        = "researcher"
      SPEC_WRITER       = "spec-writer"
      PLANNER           = "planner"
      BACKEND_CODER     = "backend-coder"
      FRONTEND_CODER    = "frontend-coder"
      CHORES_CODER      = "chores-coder"
      STAFF_REVIEWER    = "staff-reviewer"
      SECURITY_REVIEWER = "security-reviewer"
      DESIGN_REVIEWER   = "design-reviewer"
      VERIFIER          = "verifier"
      UNBLOCKER         = "unblocker"
      REBASER           = "rebaser"
      ARBITRATOR        = "arbitrator"
      DEPLOY_ASSESSOR   = "deploy-assessor"
      COPILOT           = "copilot"

      # The two coders that build a plan as a pair.
      BUILDERS = [BACKEND_CODER, FRONTEND_CODER].freeze

      # Decided, with no `agents/*.md` yet. Empty since plan 031.00 gave the
      # last two reviewers their files; kept, so the next name decided ahead
      # of its file has somewhere to wait.
      PLANNED = [].freeze

      # @return [Array<String>] every name above, in the order written
      def self.all = constants.filter_map { const_get(it) if const_get(it).is_a?(String) }
    end
  end
end
