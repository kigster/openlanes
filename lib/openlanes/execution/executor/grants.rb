# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What an agent may not use: the tools and commands withheld from it,
      # and what its `may:` lifts. Every grant is read from `agents/*.md`,
      # and {UNGRANTABLE} is subtracted from every one of them.
      module Grants
        # Tools no agent may use under this autonomy level, whatever its definition
        # asks for. Git itself is reachable through Bash, which is why the
        # after-check exists as well.
        #
        # The exception is an agent that declares `network: true`. Closed is the
        # right default — most specialists here read the repository and write to
        # it, and a model that decides to go looking online mid-task is a model
        # doing something nobody asked for. But a researcher inverts that: reading
        # the internet is the entire job, and denying it silently produced an
        # agent that ran, found nothing, and reported success.
        DENIED_TOOLS = %w[WebFetch WebSearch].freeze

        # Commands that leave the machine, denied to every agent by default.
        #
        # These are passed to `claude` as `Bash(<command>:*)` tool specifiers, so
        # they are withheld rather than merely discouraged. This list spent a while
        # as a regular expression that nothing referenced — a guard in the shape of
        # a constant, enforcing nothing — which is exactly how `gh pr review` came
        # to be reachable by an agent nobody had granted it to.
        #
        # `git rebase` is here because the harness owns the rebase onto the
        # default branch ({Vcs::Refresh}): an agent resolving a stopped one only
        # edits and stages, and a `--continue`, `--skip` or `--abort` of its own
        # would move HEAD inside the window the after-check guards.
        FORBIDDEN_COMMANDS = [
          "git push", "git commit", "git rebase",
          "gh pr create", "gh pr edit", "gh pr merge",
          "gh pr review", "gh pr comment",
          "gh release create"
        ].freeze

        # The subset no agent's `may:` can lift, however its definition is written.
        #
        # Pushing and merging change a branch everybody else builds on, and an
        # unattended loop doing either has no way to be wrong quietly. Reviewing
        # does not: an approval is reversible, visible, and attributable to the
        # identity that made it. That difference is the whole line between
        # `staff-reviewer` approving and `staff-reviewer` merging.
        #
        # A rebase is the harness's alone for the same reason a merge is: it
        # rewrites the branch a pull request is built from, and the harness
        # pushes that rewrite with a lease only it can check.
        UNGRANTABLE = ["git push", "gh pr merge", "git rebase"].freeze

        module_function

        # What this particular agent may not touch: the network tools unless it
        # asked for them, plus every forbidden command it has not been granted.
        # Both decisions are recorded in a reviewable file rather than passed as a
        # flag by whoever happened to start the run.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @return [Array<String>]
        def denied_for(agent)
          tools = agent.network ? [] : DENIED_TOOLS
          tools + denied_commands(agent).map { |command| "Bash(#{command}:*)" }
        end

        # @param agent [OpenLanes::Agents::Agent]
        # @return [Array<String>] commands withheld from this agent
        def denied_commands(agent) = FORBIDDEN_COMMANDS - granted_to(agent)

        # @param agent [OpenLanes::Agents::Agent]
        # @return [Array<String>] what its `may:` actually buys it
        def granted_to(agent) = agent.may - UNGRANTABLE
      end
    end
  end
end
