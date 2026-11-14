# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Lanes < Step
        # The two ends of a discard (W9) that are not stopping agents: what
        # refuses one before any agent is stopped, and, once the last of them
        # has gone, the worktree reset and the folder sent back.
        class Discards < Step
          # @param ordinal [String]
          # @param jobs [Array<OpenLanes::Engine::Dispatcher::Job>] the plan's agents
          # @return [Symbol, nil] the state the work started from (see {#started_from})
          # @raise [OpenLanes::Error] with the reason it cannot be done
          def check!(ordinal, jobs)
            no_worktree! if !runner.isolated? || runner.dry_run?
            subject = fresh_by(Plans::Ordinal.parse(ordinal)) or raise OpenLanes::Error, "there is no plan #{ordinal}"
            from = started_from(jobs)
            refusal = subject.machine.retreat_refusal(from) and raise OpenLanes::Error, "#{ordinal} cannot go back: #{refusal}"
            from
          end

          # Discards whose agents have all gone: the worktree is reset and the
          # folder moved back. A finished one stays one tick, for
          # {Live::Commands} to reply from, and is dropped on the next.
          #
          # @return [void]
          def complete
            discarding.delete_if { |_, discard| discard.finished? }
            discarding.each_value do |discard|
              next if running.any? { plan_of(it) == discard.ordinal }

              discard.status, discard.reason = throw_back(discard)
            end
          end

          private

          def no_worktree!
            raise OpenLanes::Error,
              "discard resets the plan's own worktree, and this run has none: under --isolation shared " \
              "or a dry run every agent works in the main checkout, which a reset would wipe. " \
              "Use stop on each agent instead."
          end

          # The state the discarded work started from: each job's {Job#from},
          # the state the plan showed when it was picked. Only an agent with
          # `starts_as` moved the folder on, so stepping back from the folder's
          # own state sent every other agent's plan one phase too far (issue
          # #173). A pair can be picked on either side of backend-coder's
          # `starts_as` rename, so the earliest of its starts wins: the one with
          # the longest road ahead of it.
          #
          # @param jobs [Array<OpenLanes::Engine::Dispatcher::Job>]
          # @return [Symbol, nil] nil when no agent was running
          def started_from(jobs) = jobs.map(&:from).compact.uniq.max_by { Plans::StateMachine.onward(it).size }

          # @param discard [OpenLanes::Engine::Dispatcher::Discard]
          # @return [Array(String, String)] status and reason
          def throw_back(discard)
            ordinal = discard.ordinal
            subject = fresh_by(Plans::Ordinal.parse(ordinal)) or return ["refused", "#{ordinal}'s folder vanished"]
            reset = runner.worktree.reset(subject.feature)
            from = subject.status
            to = subject.machine.retreat!(discard.from)
            finished_plans.delete(ordinal)
            UI.log("discarded: #{from} -> #{to}", plan: ordinal)
            ["done", "#{ordinal} #{reset ? "reset" : "had no worktree to reset"}, and #{moved(from, to)}"]
          rescue OpenLanes::Error => e
            ["refused", "#{ordinal}'s agents were stopped, but: #{e.message}"]
          end

          def moved(from, to) = to.key == from.key ? "stays at #{to}, where its work started" : "went back from #{from} to #{to}"
        end
      end
    end
  end
end
