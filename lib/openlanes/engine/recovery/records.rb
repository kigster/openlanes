# frozen_string_literal: true

module OpenLanes
  module Engine
    module Recovery
      # The harness signs in `state.json`, as the agents do through
      # `openlanes state sign`; nothing it writes lands in the plan's
      # documents. A dry run writes no stage and no resume record, and a
      # harness that cannot write the file reports it and carries on: the
      # folder name and the ledger still say what happened.
      class Records
        # @param dry_run [Boolean]
        def initialize(dry_run:)
          @dry_run = dry_run
        end

        # One round in the plan's own `state.json`.
        #
        # @param round [Round]
        # @param fields [Hash] as {Plans::PlanState#stage!} takes them
        # @return [void]
        def stage!(round, **fields)
          return if @dry_run

          Plans::PlanState.for(round.subject.feature.path).stage!(agent: round.agent.name, round: round.round, **fields)
        rescue SystemCallError, OpenLanes::Error => e
          UI.log("state.json not written: #{e.message}", level: :warn, plan: round.subject.feature.ordinal.to_s)
        end

        # The resume record the agent did not leave: killed when its grace
        # ran out, dead, or stopped by the harness. Only what the harness
        # saw, its last ledger line and its last transcript phrase, because
        # that is all it knows; an agent's own record of this round or a
        # later one stays, which {Plans::LastKnownState#supersedes?} decides
        # under the plan lock. Pids, tokens and exit codes stay in
        # `openlanes-state.json`.
        #
        # @param round [Round]
        # @param reason [String] why the agent stopped
        # @param last [Plans::Ledger::Entry, nil] read before the harness
        #   wrote its own Interrupted line
        # @param phrase [String, nil] the transcript's last phrase
        # @return [void]
        def resume(round, reason, last: last_line(round), phrase: nil)
          return if @dry_run

          entry = Plans::LastKnownState.new(source: "harness", round: round.round, status: "Interrupted", note: note(reason, last, phrase))
          Plans::PlanState.for(round.subject.feature.path).record_last_known(round.agent.name, entry)
        rescue SystemCallError, OpenLanes::Error => e
          UI.log("resume record not written: #{e.message}", level: :warn, plan: round.subject.feature.ordinal.to_s)
        end

        # @param round [Round]
        # @param reason [String]
        # @return [void]
        def interrupted(round, reason)
          Plans::PlanState.for(round.subject.feature.path).sign!(agent: round.agent.name, round: round.round, status: "Interrupted", note: reason)
        end

        # @param round [Round]
        # @return [Plans::Ledger::Entry, nil] the agent's last ledger line on the plan
        def last_line(round)
          agent = round.agent
          Plans::Ledger.last_for(Plans::Ledger.read(round.subject.feature.path, agent.ledger), agent.name)
        end

        private

        # @return [String]
        def note(reason, last, phrase)
          seen = "last ledger line: #{last.status}, round #{last.round}#{": #{last.note}" if last.note}" if last
          [reason, seen, ("last seen: #{phrase}" if phrase && !phrase.empty?)].compact.join("; ")
        end
      end
    end
  end
end
