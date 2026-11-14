# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Assign < Step
        # No agent starts while `.openlanes.yml` has no
        # `desired_codebase_quality:` (plan 035): every level changes what the
        # builders and reviewers aim for, so work done before the answer would
        # be done to the wrong standard. The question goes on the first plan in
        # scope, where the page shows it, and is said once in the log. The
        # answer lifts the gate on the next tick: {Config.current} rereads a
        # changed file.
        class QualityGate < Step
          # @return [Boolean] whether dispatch waits on the answer
          def awaited?
            return false unless runner.awaiting_quality?

            asker = runner.in_scope.first
            asker ? ask(asker) : say_nowhere
            true
          end

          private

          # With nobody in scope there is no folder to hang the question on,
          # and that is said too, rather than waiting with no line.
          def say_nowhere
            say("waiting: desired_codebase_quality is not set in #{Config::FILE}; " \
                "no plan in scope to ask #{QualityQuestion::NAME} on")
          end

          def ask(asker)
            QualityQuestion.ask!(asker.feature.path)
            say("waiting: desired_codebase_quality is not set in #{Config::FILE}; " \
                "answer #{QualityQuestion::NAME} (#{Config::QUALITIES.join(", ")}) before any agent starts",
              plan: asker.feature.ordinal.to_s)
          end

          # Once per run, whichever of the two lines comes first.
          def say(line, **)
            return if @said

            UI.log(line, **)
            @said = true
          end
        end
      end
    end
  end
end
