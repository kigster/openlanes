# frozen_string_literal: true

module OpenLanes
  module Engine
    module Recovery
      # Rounds of a plan's current visit that `state.json` calls Started and
      # nothing else accounts for: the run's state file does not know them,
      # and no older release left a `run` on them.
      #
      # That is `state.json` reaching an engine whose state file never held
      # the stage: another machine's, a wiped state directory, or an engine
      # killed between writing the stage and saving its own file. Counted as
      # it stood, the stage held the agent at its budget for good: nothing
      # started, a Started round raised no request, and the run said
      # `idle: nothing to do` over a parked plan. {Stranded} resumes them as
      # it does the rest.
      #
      # A plan whose lock another live run holds is left alone: its Started
      # stage is that run's agent, working.
      class Orphans
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Array<Hash>] the stages, as `state.json` has them
        def call(subject)
          path = subject.feature.path
          return [] if Plans::Lock.read(path)&.held_elsewhere?

          state = Plans::PlanState.for(path)
          # One with a `run` is {Plans::PlanState#stranded}'s to judge, by its pid.
          Plans::Rounds.from(state).started(subject.status.key, moves: state.moves).reject { it.key?("run") }
        end
      end
    end
  end
end
