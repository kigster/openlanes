# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # verifier signed. The engine commits, comments and labels from its
        # report; the folder moves only on a rejection.
        class Verify < Step
          # @param round [Completed]
          # @return [OpenLanes::Engine::Runner::Attempt]
          def call(round)
            base = round.base
            verdict = Verdicts.of(round.entry)
            result = ruled(round, verdict)
            return base.with(ok: false, status: "Completed", note: "#{base.note}; signed neither verified nor rejected") unless verdict
            return base.with(ok: false, status: "Completed", note: "#{base.note}; no open pull request to verify") unless result

            wake!
            base.with(status: "Completed", to: result.to || round.job.state, note: "#{base.note}; #{result.note}")
          end

          private

          def ruled(round, verdict)
            driver = runner.verification
            case verdict
            when :rejected then driver.reject(round.job.task, round.subject)
            when :verified then driver.pass(round.job.task, round.subject)
            end
          end
        end
      end
    end
  end
end
