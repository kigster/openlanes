# frozen_string_literal: true

require "shellwords"

module OpenLanes
  module Execution
    class Prompt
      # How an agent gets to write in its own plan folder. The engine claims
      # the folder in alock (`<folder>/**`, held by `openlanes@<host>:<pid>`)
      # before the job starts, to keep agents outside openlanes away from it.
      # alock does not see the agent as the engine's, so the agent's own
      # `acquire` inside that folder is refused, and an agent told "a refused
      # acquire means stop" never wrote its plan: 004.00 in laser-cutter
      # spent every round it had that way. The agent takes the claim over
      # with `alock break` and then claims files as usual. It does not claim
      # the whole folder again, which would shut out a pair's partner.
      module PlanLock
        # The paragraph; {.handover} fills in the agent, the folder's scope
        # and its plans directory, in that order.
        TEXT = <<~TEXT.chomp
          The harness claimed your plan folder for you before you started
          (holder `openlanes@…`), so an `acquire` inside it is refused. That
          claim is yours to take over: break it once, then claim files as
          usual.

              AGENT_ID=%s alock break %s --dir %s

          Break nothing else. Any other refusal, including one inside the plan
          folder by a holder that is not `openlanes@…`, is another agent's
          claim: work on something else.
        TEXT

        module_function

        # @param agent [String] the agent's name, its AGENT_ID
        # @param folder [String] the plan folder, as the engine claimed it
        # @return [String] the prompt's paragraph on taking the claim over
        def handover(agent, folder)
          format(TEXT, agent, Shellwords.escape("#{File.basename(folder)}/**"), Shellwords.escape(File.dirname(folder)))
        end
      end
    end
  end
end
