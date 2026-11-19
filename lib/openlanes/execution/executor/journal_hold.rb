# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The record, in the plan's state.json, of how much of the journal a
      # resumed session already holds, so the round that resumes it is sent
      # only what came after ({JournalWindow}).
      module JournalHold
        module_function

        # The record of what the resumed session holds of the journal is dropped
        # before the session runs again, and written back by {.hold} only if
        # the round ends with it intact. A round that is killed with the
        # engine, or compacts, then leaves nothing for the next one to trust,
        # and that one is sent the whole journal.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [void]
        def forget(agent, subject)
          Plans::PlanState.for(subject.feature.path).forget_held!(agent.name)
        rescue SystemCallError, OpenLanes::Error => e
          UI.log("journal record not cleared: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s, agent: agent.name)
        end

        # Note that the session this invocation ended in holds the journal as it
        # now stands. Not when any session of the invocation was compacted, by a
        # person or by the CLI at its threshold: a summary keeps what the model
        # chose to keep. A folder renamed under the agent is left alone too,
        # since writing there would mint a state.json in a folder nobody reads.
        #
        # @param attempt [OpenLanes::Execution::Executor::Attempt]
        # @return [void]
        def hold(attempt)
          path = attempt.subject.feature.path
          session = attempt.handle.session
          return unless session && File.directory?(path) && !attempt.sessions.compacted?

          Plans::PlanState.for(path).hold!(agent: attempt.agent.name, session:)
        rescue SystemCallError, OpenLanes::Error => e
          UI.log("journal record not written: #{e.message}", level: :warn, plan: attempt.plan, agent: attempt.agent.name)
        end
      end
    end
  end
end
