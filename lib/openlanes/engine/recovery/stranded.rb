# frozen_string_literal: true

module OpenLanes
  module Engine
    module Recovery
      # Started stages a dead run left behind get the harness's own line, and
      # the agent starts again from its resume note without spending a round:
      # the harness died, not the agent. Asking a person to keep or discard
      # the work got the same answer every time, so nobody is asked.
      #
      # Two records can say a stage was stranded: the run's own state file,
      # which holds the pid and host of every stage it started, and the
      # plan's `state.json`, whose stages carry a `run` only when an older
      # release wrote them. The pid and host are about one machine, so new
      # stages no longer put them in a committed file; the second check stays
      # so a crash under the old layout still resumes. A stage either names
      # is resumed once.
      class Stranded
        # @param runner [Runner]
        # @param state [StateFile, nil] nil under a dry run
        # @param records [Records]
        # @param clock [#now]
        def initialize(runner:, state:, records:, clock:)
          @runner = runner
          @state = state
          @records = records
          @clock = clock
        end

        # @param skip [Array<Array(String, String, Integer)>] stages taken
        #   back by {Reattach}, which are not stranded
        # @return [void]
        def call(skip: [])
          resumed = from_state_file(skip) + skip
          from_plan_states(resumed) unless @runner.dry_run?
          @state&.begin_run!(root: @runner.root)
        end

        private

        # @param skip [Array<Array(String, String, Integer)>]
        # @return [Array<Array(String, String, Integer)>] what was resumed
        def from_state_file(skip)
          return [] unless @state

          @state.load
          @state.stranded.filter_map do |ordinal, stage|
            next if skip.include?([ordinal, stage["agent"], stage["round"]])

            subject = @runner.tree.reload.find(Plans::Ordinal.parse(ordinal)) or next
            interrupt(subject, stage["agent"], stage["round"]) unless @runner.foreign?(subject)
          end
        end

        # @param resumed [Array] what the state file already resumed, added to
        # @return [void]
        def from_plan_states(resumed)
          @runner.in_scope.reject { @runner.foreign?(it) }.each do |subject|
            Plans::PlanState.for(subject.feature.path).stranded.each do |stage|
              next if resumed.include?([subject.feature.ordinal.to_s, stage["agent"], stage["round"]])

              resumed << interrupt(subject, stage["agent"], stage["round"])
            end
          end
        end

        # @return [Array(String, String, Integer), nil] what was resumed
        def interrupt(subject, name, number)
          agent = @runner.agents.find(name) or return nil
          round = Round.new(subject:, agent:, round: number)
          @records.resume(round, DIED)
          @records.interrupted(round, DIED)
          tell(round)
          @state&.record(subject.feature.ordinal.to_s, agent: agent.name, round: number, status: "Interrupted", exit: DIED)
          @records.stage!(round, status: "Interrupted", note: DIED, finished_at: @clock.now.iso8601)
          [subject.feature.ordinal.to_s, agent.name, number]
        end

        # @return [void]
        def tell(round)
          Plans::Mailbox.new(dir: round.subject.feature.path).append(from: HARNESS,
            to: round.agent.name,
            body: "RESUME: the harness died during your round #{round.round}; carry on from your last resume note")
        end
      end
    end
  end
end
