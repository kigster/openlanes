# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Who works what next: the folders' names reconciled with their
      # contents, the plans in scope walked in the order that unblocks the
      # most, and the first agent that may take each one started, until
      # every slot is full. When nothing can start, it says what the run is
      # waiting for, once.
      class Assign < Step
        # @param desk [Desk]
        # @param start [Start]
        # @param rescan [Integer] idle ticks between rescans while staying
        def initialize(desk, start:, rescan:)
          super(desk)
          @start = start
          @rescan = rescan
          @idle_ticks = 0
          @said = nil
        end

        # @return [void]
        def dispatch
          ask_for_rounds
          refusals.clear
          started = 0
          while running.size < runner.jobs && (pair = next_dispatchable)
            # Lost to another machine between the check and the claim, or Redis
            # cannot say who holds it (W31). Either way the rest of this pass goes
            # on without the plan: with Redis gone `foreign?` answers false, so
            # without remembering the refusal `next_dispatchable` hands the same
            # plan back and the tick never returns.
            unless runner.claim(pair.last)
              refusals << pair.last.feature.ordinal.to_s
              next
            end

            started_now = start(*pair)
            # Lost to an agent outside openlanes (W31): the rest of this pass
            # goes on without that plan, and the next listing shows its holder.
            next if started_now.nil?
            # Lost the lock file to another run on this machine: the next tick
            # reads its lock and steps around the plan.
            break unless started_now

            started += 1
          end
          settle_idle(started) if stay?
        end

        # Whether an idle staying run skips this tick's dispatch. Dispatching
        # reloads the tree and runs `resync dirs` over it, which is cheap once
        # but not twice a second for hours with nothing to find, so an idle run
        # looks again every {RESCAN} ticks, or at once when woken. Commands,
        # drains and the board still run every tick; only the scan waits.
        #
        # @return [Boolean]
        def resting?
          return false unless stay? && idle && quiet?

          @idle_ticks += 1
          return true unless wake || @idle_ticks >= @rescan

          self.wake = false
          @idle_ticks = 0
          false
        end

        # The next agent and plan to start, honouring a `next:` an agent wrote
        # over definition order.
        #
        # @return [Array(OpenLanes::Agents::Agent, OpenLanes::Plans::Subject), nil]
        def next_dispatchable
          reconcile
          # A 💣 stops new work, not work under way: agents already running
          # finish, and their plans settle, while nothing else starts.
          return nil if runner.halted?
          # Redis lost (W32): the agents under way are paused, and nobody new
          # starts until it answers, since no claim could be checked.
          return nil if Execution::Control.paused?
          return nil if quality_awaited?

          @dependencies = runner.dependencies(except: untouchable)
          @global_lock = runner.global_lock(except: untouchable)
          lock_clock&.call(@global_lock)
          blockers_first(runner.in_scope).each do |subject|
            working = running.select { plan_of(it) == subject.feature.ordinal.to_s }.map { it.task.agent }
            # After {#reconcile} this is the folder's name. On a dry run, which
            # renames nothing, it is what the name would have become. A plan an
            # agent is in right now is never reconciled, so its contents are
            # not asked: see {#partners_only}.
            state = working.empty? ? runner.effective_status(subject) : subject.status
            next if Plans::StateMachine::SETTLED.include?(state.key) || runner.stopped?(state)
            next if finished_plans.include?(subject.feature.ordinal.to_s)
            # Verified and waiting on CI: the engine's to settle, not verifier's.
            next if runner.verification&.awaiting_ci?(subject)
            # deploy-assessor ruled on this visit to 🏁: the merges are the engine's.
            next if runner.merging&.assessed?(subject)
            next if runner.foreign?(subject) || discarding.key?(subject.feature.ordinal.to_s)
            next if held?(subject)
            next if locked_elsewhere?(subject)
            next if held_outside?(subject) || refusals.include?(subject.feature.ordinal.to_s)

            refusal = budget_refusal(subject)
            announce_budget(subject, refusal)
            next if refusal
            # A stopped rebase holds the checkout until the harness has
            # continued or aborted it; a partner started now would build on
            # conflict markers.
            next if running.any? { plan_of(it) == subject.feature.ordinal.to_s && it.rebase }

            candidates = partners_only(Agents::Routing.offer(runner.agents, state, subject), working, state)
            preferred = preferred_agents[subject.feature.ordinal.to_s]
            candidates = candidates.sort_by { |a| a.name == preferred ? 0 : 1 } if preferred
            agent = candidates.find { |a| eligible?(a, subject) }
            return [agent, subject] if agent
          end
          nil
        end

        # @param subjects [Array<OpenLanes::Plans::Subject>] the plans in scope
        # @return [String] what an idle run is waiting for
        def idle_reason(subjects)
          # Finished plans move into archive/ (N3), so an empty top level after
          # a run that shipped everything is "finished", not "no plans yet".
          # `[].all?` is true, which is the finished case when every plan has
          # left the top level; an empty *scope* with work still sitting
          # elsewhere is not that, and under R4 it is the quality gate.
          if subjects.empty?
            all = runner.tree.everything.reload.subjects
            return "idle: no plans yet; create one from the page or with openlanes create" if all.empty?
            if all.all? { FINISHED.include?(it.status.key) }
              return "idle: every plan is finished; create the next one from the page"
            end
            if runner.awaiting_quality?
              return "idle: desired_codebase_quality is not set in #{Config::FILE}; " \
                     "no plan in scope to ask #{QualityQuestion::NAME} on"
            end
          end
          if subjects.all? { FINISHED.include?(it.status.key) }
            return "idle: every plan is finished; create the next one from the page"
          end

          bombs = runner.halted_by.map { it.feature.ordinal.to_s }
          return "idle: halted by 💣 #{bombs.join(", ")}; answer, or resume anyway from the page" unless bombs.empty?

          # Every reason, not the first: a run idle on answers and on a held
          # plan named only the answers, and the held plan looked forgotten.
          reasons = []
          failures = unblocking.failures
          failed = waiting.select { failures.key?(it) }
          blocked = waiting - failed
          reasons << "waiting for answers on #{blocked.join(", ")}" unless blocked.empty?
          unless failed.empty?
            reasons << "unblock failed on #{failed.map { "#{it} (#{failures[it]})" }.join(", ")}; " \
                       "edit blocked.md to try again"
          end
          reasons.concat(verifying.map { |plan, note| "#{plan} #{note}" })
          held = runner.held(runner.dependencies(except: untouchable), runner.global_lock(except: untouchable))
          reasons << "held by dependencies: #{held.map { |o, why| "#{o} #{why}" }.join("; ")}" unless held.empty?
          over = budget_holds
          reasons << "held by budget: #{over.map { |o, why| "#{o} #{why}" }.join("; ")}" unless over.empty?
          reasons.empty? ? "idle: nothing to do" : "idle: #{reasons.join("; ")}"
        end

        # Plans that others wait for go first, so the work that unblocks the
        # most is started soonest. Stable: plans nobody waits for keep the
        # tree's order among themselves, and so do the blockers.
        #
        # @param subjects [Array<OpenLanes::Plans::Subject>]
        # @return [Array<OpenLanes::Plans::Subject>]
        def blockers_first(subjects)
          deps = @dependencies || runner.dependencies
          subjects.each_with_index.sort_by { |s, i| [deps.blocks_of(s.feature.ordinal).empty? ? 1 : 0, i] }.map(&:first)
        end

        private

        def_delegators :@start, :start

        # After a dispatch that started nobody: idle when nothing else is under
        # way, and said once per change, so the log reads as a story rather
        # than a heartbeat.
        #
        # @param started [Integer] agents this dispatch started
        # @return [void]
        def settle_idle(started)
          self.idle = started.zero? && quiet?
          subjects = runner.in_scope
          said = idle ? idle_reason(subjects) : nil
          UI.log(said) if said && said != @said
          @said = said
        end

        # No agent starts while `.openlanes.yml` has no `desired_codebase_quality:`
        # (plan 035): every level changes what the builders and reviewers aim
        # for, so work done before the answer would be done to the wrong
        # standard. The question goes on the first plan in scope, where the
        # page shows it, and is said once in the log. With nobody in scope
        # there is no folder to hang the question on, and that is said too,
        # rather than waiting with no line. The answer lifts the gate on the
        # next tick: {Config.current} rereads a changed file.
        #
        # @return [Boolean]
        def quality_awaited?
          return false unless runner.awaiting_quality?

          asker = runner.in_scope.first
          unless asker
            @quality_said ||= UI.log("waiting: desired_codebase_quality is not set in #{Config::FILE}; " \
                                     "no plan in scope to ask #{QualityQuestion::NAME} on") || true
            return true
          end

          QualityQuestion.ask!(asker.feature.path)
          @quality_said ||= UI.log("waiting: desired_codebase_quality is not set in #{Config::FILE}; " \
                                   "answer #{QualityQuestion::NAME} (#{Config::QUALITIES.join(", ")}) before any agent starts",
            plan: asker.feature.ordinal.to_s) || true
          true
        end

        # The dependency gate: a plan whose `depends_on:` names anything not yet
        # ✅, or which sits on a cycle, is not started this tick. Nor is one the
        # refactor gate holds (R6): a `global-lock-required` plan waiting for
        # every open branch to close, or anything queued behind it. Kept out of
        # {#next_dispatchable} so the rule can be read, and changed, alone.
        #
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Boolean]
        def held?(subject)
          ordinal = subject.feature.ordinal
          !@dependencies.reason(ordinal).nil? || !@global_lock.reason(ordinal).nil?
        end

        # One agent at a time on a plan, except a pair working the same state.
        #
        # A plan with an agent in it is judged by its folder's name, never by
        # what its contents would justify. Asking the contents is how the
        # minesweeper trial ran its whole chain inside ⚪ New: researcher wrote her
        # `## Research` chapter, the next tick saw a Researched plan and started
        # spec-writer beside her, and researcher's own Completed then found a partner running
        # and held the folder where it was. Every later agent repeated it, so
        # the folder never moved and backend-coder and frontend-coder were building on a plan whose
        # name still said nobody had researched it.
        #
        # @param candidates [Array<OpenLanes::Agents::Agent>]
        # @param working [Array<OpenLanes::Agents::Agent>] already on the plan
        # @param state [OpenLanes::Plans::Status] the folder's state
        # @return [Array<OpenLanes::Agents::Agent>]
        def partners_only(candidates, working, state)
          return candidates if working.empty?

          team = runner.agents.team_for(state).map(&:name)
          return [] unless working.all? { team.include?(it.name) }

          candidates.select { team.include?(it.name) }
        end

        # A folder's name can lag its contents: a run killed before its rename,
        # a plan.md written by hand, a resync nobody ran. So the names are
        # reconciled before every dispatch, the way `resync dirs` would, and a
        # ⚪ folder that already holds a plan goes to the pair under its honest
        # name rather than to researcher under its stale one. Plans an
        # agent is working in right now are left alone: the prompt names the
        # folder by path, and moving it under a running agent would strand
        # every write it makes afterwards. Nor is a plan another machine holds
        # touched: its name is that machine's to change. Then the blocked plans
        # age (plan 009), so a 💣 is in place before anyone is assigned.
        #
        # @return [void]
        def reconcile
          busy = untouchable
          Lifecycle::Resync::Dirs.new(tree: runner.tree.reload, except: busy).call(commit: !runner.dry_run?)
          fast_forward(busy) unless runner.dry_run?
          runner.age!(except: busy)
        end

        # Plans whose `starts:` skips research, rewriting or planning are moved past
        # those phases before anyone is assigned, so the first agent they meet
        # is the one that value starts with. A plan may take more than one hop
        # in a tick: a plan already at 📋 with a `building` spec still goes on to ⭐,
        # since no agent works it in between and a run could otherwise settle
        # at 📋 with the builder never asked.
        #
        # @param busy [Array<String>] ordinals an agent is working right now
        # @return [void]
        def fast_forward(busy)
          runner.in_scope.each do |subject|
            next if busy.include?(subject.feature.ordinal.to_s)

            Plans::StateMachine::SPINE.size.times do
              moved = Lifecycle::Lanes.advance(subject, commit: true) or break
              UI.log("starts: #{moved.first} -> #{moved.last}", plan: subject.feature.ordinal.to_s)
              subject = Plans::Tree.new(dir: runner.tree.dir).find(subject.feature.ordinal) or break
            end
          end
        end

        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Boolean]
        def eligible?(agent, subject)
          ordinal = subject.feature.ordinal.to_s
          # A capped plan is the arbitrator's; one it is being asked about
          # waits for the ruling, which may move it.
          return false if runner.arbitration&.holds?(subject) || arbitrating_now.include?(ordinal)
          return false if running.any? { |j| j.task.agent.name == agent.name && j.task.subject.feature.ordinal.to_s == ordinal }

          past = history[[ordinal, agent.name]].select { |h| h[:state] == subject.status.key }
          return true if past.empty?
          return false if %w[Completed Blocked].include?(past.last[:status])

          past.size < rounds_for(agent) + extensions.rounds(subject.feature.path, agent.name, subject.status.key)
        end

        # Agents that used every round they had on a plan's state without
        # finishing ask for another. Before the dispatch, so a round granted
        # on its own starts in the same pass.
        #
        # @return [void]
        def ask_for_rounds
          return if runner.dry_run? || runner.halted?

          busy = untouchable
          # Fresh from disk: a round started on a plan renames it without
          # touching the cached tree, and an exhausted Building agent read
          # against a stale Planned would never be asked about.
          runner.tree.reload
          runner.in_scope.each do |subject|
            next if busy.include?(subject.feature.ordinal.to_s) || Plans::StateMachine::SETTLED.include?(subject.status.key)

            Agents::Routing.offer(runner.agents, subject.status, subject).each do |agent|
              last = out_of_rounds(agent, subject) or next
              extensions.exhausted(subject.feature.path, agent.name, subject.status.key, last[:round])
            end
          end
        end

        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Hash, nil] the agent's last round on the plan's state, when it was its last allowed one
        def out_of_rounds(agent, subject)
          past = history[[subject.feature.ordinal.to_s, agent.name]].select { |h| h[:state] == subject.status.key }
          return nil if past.empty? || %w[Completed Blocked Started].include?(past.last[:status])
          return nil if past.size < rounds_for(agent) + extensions.rounds(subject.feature.path, agent.name, subject.status.key)

          past.last
        end
      end
    end
  end
end
