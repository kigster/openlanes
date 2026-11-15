# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Assign < Step
        # What an idle run is waiting for, in one line.
        class IdleReason < Step
          # Said when nothing is left to do in scope.
          ALL_FINISHED = "idle: every plan is finished; create the next one from the page"

          # @param desk [Desk]
          # @param stalls [Stalls] names the agents held by failed starts
          def initialize(desk, stalls: Stalls.new(desk))
            super(desk)
            @stalls = stalls
          end

          # @param subjects [Array<OpenLanes::Plans::Subject>] the plans in scope
          # @return [String]
          def call(subjects)
            empty_scope(subjects) || finished(subjects) || halted || listed(reasons(subjects))
          end

          private

          # Finished plans move into archive/ (N3), so an empty top level
          # after a run that shipped everything is "finished", not "no plans
          # yet". An empty *scope* with work still sitting elsewhere is not
          # that, and under R4 it is the quality gate; otherwise it falls
          # through to {#finished}, since `[].all?` is true.
          def empty_scope(subjects)
            return nil unless subjects.empty?

            all = runner.tree.everything.reload.subjects
            return "idle: no plans yet; create one from the page or with openlanes create" if all.empty?
            return ALL_FINISHED if all.all? { FINISHED.include?(it.status.key) }

            no_quality if runner.awaiting_quality?
          end

          def no_quality
            "idle: desired_codebase_quality is not set in #{Config::FILE}; " \
              "no plan in scope to ask #{QualityQuestion::NAME} on"
          end

          def finished(subjects) = (ALL_FINISHED if subjects.all? { FINISHED.include?(it.status.key) })

          def halted
            bombs = runner.halted_by.map { it.feature.ordinal.to_s }
            "idle: halted by 💣 #{bombs.join(", ")}; answer, or resume anyway from the page" unless bombs.empty?
          end

          # Every reason, not the first: a run idle on answers and on a held
          # plan named only the answers, and the held plan looked forgotten.
          def reasons(subjects)
            waiting_reasons + verifying.map { |plan, note| "#{plan} #{note}" } + start_reasons(subjects) + hold_reasons
          end

          # A CLI that cannot log in, and agents whose starts keep failing.
          def start_reasons(subjects) = [cli_pause.reason, @stalls.reason(subjects)].compact

          def waiting_reasons
            failures = unblocking.failures
            failed = waiting.select { failures.key?(it) }
            blocked = waiting - failed
            [("waiting for answers on #{blocked.join(", ")}" unless blocked.empty?),
             (unless failed.empty?
                "unblock failed on #{failed.map { "#{it} (#{failures[it]})" }.join(", ")}; edit blocked.md to try again"
              end)].compact
          end

          def hold_reasons
            held = runner.held(runner.dependencies(except: untouchable), runner.global_lock(except: untouchable))
            over = budget_holds
            [("held by dependencies: #{pairs(held)}" unless held.empty?), ("held by budget: #{pairs(over)}" unless over.empty?)].compact
          end

          def pairs(map) = map.map { |o, why| "#{o} #{why}" }.join("; ")

          def listed(found) = found.empty? ? "idle: nothing to do" : "idle: #{found.join("; ")}"
        end
      end
    end
  end
end
