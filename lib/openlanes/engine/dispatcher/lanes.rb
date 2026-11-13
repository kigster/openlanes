# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What a person, or another machine, does to a whole plan while the
      # run is under way: throw its work away, take its claim, stop it, or
      # put it back on the board. Each one stops the plan's agents first and
      # leaves the rest to a later tick, so no command holds the loop while
      # an agent takes its {KILL_GRACE} seconds to go.
      class Lanes < Step
        # Throw a plan's work away (W9): every agent on it is stopped, each with
        # {KILL_GRACE} seconds to finish the line it is writing, and once the
        # last is gone the plan's worktree is reset and its folder sent back
        # to the state that work started from (see {#started_from}).
        # Plan-wide, because a pair shares one worktree and a reset takes both
        # halves. What can be refused is refused here, before any agent is
        # stopped.
        #
        # @param ordinal [#to_s]
        # @return [OpenLanes::Engine::Dispatcher::Discard] finished on a later tick
        # @raise [OpenLanes::Error] with the reason it cannot be done
        def discard(ordinal)
          ordinal = ordinal.to_s
          return discarding[ordinal] if discarding.key?(ordinal)

          if !runner.isolated? || runner.dry_run?
            raise OpenLanes::Error,
              "discard resets the plan's own worktree, and this run has none: under --isolation shared " \
              "or a dry run every agent works in the main checkout, which a reset would wipe. " \
              "Use stop on each agent instead."
          end
          subject = fresh_by(Plans::Ordinal.parse(ordinal)) or raise OpenLanes::Error, "there is no plan #{ordinal}"
          jobs = running.select { plan_of(it) == ordinal }
          from = started_from(jobs)
          refusal = subject.machine.retreat_refusal(from) and raise OpenLanes::Error, "#{ordinal} cannot go back: #{refusal}"

          jobs.each do |job|
            Thread.new { job.handle.kill!(grace: KILL_GRACE, reason: :discard) }
          end
          discarding[ordinal] = Discard.new(ordinal:, from:)
        end

        # Discards whose agents have all gone: the worktree is reset and the
        # folder moved back. A finished one stays one tick, for
        # {Live::Commands} to reply from, and is dropped on the next.
        #
        # @return [void]
        def finish_discards
          discarding.delete_if { |_, discard| discard.finished? }
          discarding.each_value do |discard|
            next if running.any? { plan_of(it) == discard.ordinal }

            discard.status, discard.reason = throw_back(discard)
          end
        end

        # Plans whose claim another machine now holds (W26): their agents are
        # stopped, each with {KILL_GRACE} seconds, the plans leave this run,
        # and nothing this node does afterwards signs or renames for them.
        #
        # @param ordinals [Array<String>]
        # @return [void]
        def fence(ordinals)
          ordinals.map(&:to_s).each do |ordinal|
            fenced << ordinal unless fenced.include?(ordinal)
            runner.drop_plan(ordinal)
            running.select { plan_of(it) == ordinal }.each do |job|
              UI.log("claim lost; stopping", level: :warn, **job.task.log_fields)
              Thread.new { job.handle.kill!(grace: KILL_GRACE, reason: :fenced) }
            end
          end
        end

        # The copilot's `/stop NNN`: every agent on the plan is told STOP, and
        # the plan leaves this run so the next tick does not start it again.
        # Its claim is let go, so the plan is free for any machine.
        #
        # @param ordinal [#to_s]
        # @return [Array<String>] the keys told STOP
        # @raise [OpenLanes::Error] when the plan is neither running nor in scope
        def stop_plan(ordinal)
          ordinal = ordinal.to_s
          keys = running.select { plan_of(it) == ordinal }.map(&:key)
          if keys.empty? && !in_run?(ordinal)
            raise OpenLanes::Error, "#{ordinal} is not on this run's board: no agent is working it and it is not in scope"
          end

          told = keys.select { signal(it, Execution::Control::STOP) }
          runner.drop_plan(ordinal)
          runner.release(ordinal)
          told
        end

        # The copilot's `/restart NNN`, for a lane that lost its agent (a Redis
        # glitch, a killed process): the plan is put back in scope, the rounds
        # it used up here are forgotten, and the next tick dispatches it. A
        # plan with an agent on it already is left alone.
        #
        # @param ordinal [#to_s]
        # @return [void]
        # @raise [OpenLanes::Error] when an agent is working it, or it is not on
        #   this node's board
        def restart_plan(ordinal)
          ordinal = ordinal.to_s
          working = running.select { plan_of(it) == ordinal }.map { it.task.agent.name }
          raise OpenLanes::Error, "#{ordinal} already has an agent: #{working.join(", ")}" unless working.empty?

          subject = fresh_by(Plans::Ordinal.parse(ordinal))
          unless subject && (in_run?(ordinal) || runner.dropped?(ordinal)) && !runner.foreign?(subject)
            raise OpenLanes::Error, "#{ordinal} is not on this node's board"
          end

          runner.add_plan(subject.feature.ordinal)
          mutex.synchronize { history.delete_if { |(plan, _), _| plan == ordinal } }
          finished_plans.delete(ordinal)
          wake!
        end

        private

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
          moved = to.key == from.key ? "stays at #{to}, where its work started" : "went back from #{from} to #{to}"
          ["done", "#{ordinal} #{reset ? "reset" : "had no worktree to reset"}, and #{moved}"]
        rescue OpenLanes::Error => e
          ["refused", "#{ordinal}'s agents were stopped, but: #{e.message}"]
        end
      end
    end
  end
end
