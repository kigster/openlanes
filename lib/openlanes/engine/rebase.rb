# frozen_string_literal: true

module OpenLanes
  module Engine
    # Sees a rebase that {Vcs::Refresh} left stopped on conflicts through to
    # the end, with agents doing the resolving and the harness doing every
    # git step that moves HEAD.
    #
    # The owner's words (decision D10): "I don't want to be manually dealing
    # with git rebases onto main from worktrees and conflict resolution. This
    # is the job for the agent, whichever is best suited to do it." So a
    # conflict never becomes a question or a blocked plan. The order is:
    #
    # 1. the agent the dispatcher assigned, when it is one that builds, since
    #    it knows what the branch is for;
    # 2. bb8-resolver, the agent whose only job this is;
    # 3. abort, which restores the branch exactly, and bb8-resolver again on
    #    a later run, one step up {LADDER} each time;
    # 4. once the ladder is spent, nothing until the default branch moves:
    #    the plan works on its old base meanwhile, and the log says so.
    #
    # Agents only edit and `git add`; {Execution::Executor::FORBIDDEN_COMMANDS}
    # withholds `git rebase` and `git commit`, and HEAD stays still across
    # each agent's run because the harness continues the rebase between
    # runs, outside the window {Execution::Boundary} checks.
    class Rebase
      # The agent whose only job is a stopped rebase.
      RESOLVER = "bb8-resolver"

      # Phases whose agents wrote the branch, and so try its conflicts first.
      IMPLEMENTER_PHASES = %w[build frontend].freeze

      # Commits that may stop on conflicts in one run. A branch that conflicts
      # on more of its commits than this is better served by an abort and a
      # fresh, escalated attempt than by one agent grinding through the lot.
      STOPS = 10

      # What bb8-resolver runs as on each successive failure of the same
      # conflict: its own frontmatter first, then up a model tier, then up in
      # effort too. Its length is how many times a plan's rebase is aborted
      # before it waits for the default branch to move.
      LADDER = [{}, { model: "opus", effort: "high" }, { model: "opus", effort: "max" }].freeze

      # How one plan's rebase has gone across runs.
      #
      # @!attribute [r] failures
      #   @return [Integer] aborts so far, the step on {LADDER}
      # @!attribute [r] held_at
      #   @return [String, nil] the default-branch commit the ladder ran out on
      Tally = Data.define(:failures, :held_at)

      # @param agents [OpenLanes::Agents::Registry]
      # @param executor [#call] {Execution::Executor}, or the suite's stand-in
      def initialize(agents:, executor:)
        @agents = agents
        @executor = executor
        @mutex = Mutex.new
        @tallies = {}
      end

      # The default-branch commit a plan's rebase is waiting to see move past.
      #
      # @param ordinal [#to_s]
      # @return [String, nil]
      def hold(ordinal) = tally(ordinal).held_at

      # @param ordinal [#to_s]
      # @return [OpenLanes::Engine::Rebase::Tally]
      def tally(ordinal) = @mutex.synchronize { @tallies.fetch(ordinal.to_s) { Tally.new(failures: 0, held_at: nil) } }

      # Who resolves, in order, given how often this plan's rebase has failed.
      # The assigned agent goes first only on a first attempt: once it has
      # failed on a conflict, the escalated resolver is the better bet.
      #
      # @param agent [OpenLanes::Agents::Agent] the one the dispatcher assigned
      # @param ordinal [#to_s]
      # @return [Array<OpenLanes::Agents::Agent>]
      def resolvers(agent, ordinal)
        failures = tally(ordinal).failures
        first = failures.zero? && agent.name != RESOLVER && IMPLEMENTER_PHASES.include?(agent.phase) ? [agent] : []
        step = LADDER[failures]
        resolver = @agents.find(RESOLVER)
        first + (step && resolver ? [resolver.with(**step)] : [])
      end

      # Resolve, continue, repeat, until the rebase ends one way or the other.
      #
      # @param task [OpenLanes::Engine::Runner::Task] its `refresh` is the
      #   stopped rebase
      # @param handle [OpenLanes::Execution::Executor::Handle]
      # @yieldparam progress [OpenLanes::Execution::Transcript::Progress]
      # @return [OpenLanes::Execution::Executor::Result] the spend of every
      #   resolver run, and one line on how it ended
      def resolve(task, handle:, &on_progress)
        ordinal = task.subject.feature.ordinal.to_s
        stopped = task.refresh
        refresh = Vcs::Refresh.new(path: task.root)
        renew(ordinal, stopped.target)
        spent = []
        stops = 1
        why = "no resolver could run"

        resolvers(task.agent, ordinal).each do |resolver|
          loop do
            UI.log("rebase: #{resolver.name} resolving #{stopped.files.join(", ")}", plan: ordinal)
            result = @executor.call(resolver,
              task.subject,
              root: task.root, round: task.round, handle:,
                            rebase: stopped,
              &on_progress)
            spent << result
            return finish(ordinal, spent, why: "stopped by request", refresh:) if handle.killed
            return finish(ordinal, spent, why: "#{resolver.name}: #{result.note}", refresh:) unless refresh.rebasing?

            left = refresh.unresolved
            unless result.ok && left.empty?
              why = result.ok ? "#{resolver.name} left #{left.join(", ")} unresolved" : "#{resolver.name}: #{result.note}"
              stopped = stopped.with(files: left.empty? ? stopped.files : left)
              break
            end

            after = refresh.continue
            return finish(ordinal, spent, resolved_by: resolver.name, base: stopped.base, stops:) if after.kind == :rebased
            return finish(ordinal, spent, why: after.reason, refresh:) unless after.conflicted?

            stops += 1
            return finish(ordinal, spent, why: "more than #{STOPS} commits conflicted", refresh:) if stops > STOPS

            stopped = after
          end
        end
        finish(ordinal, spent, why:, refresh:)
      rescue StandardError => e
        finish(ordinal, spent || [], why: "#{e.class}: #{e.message}", refresh:)
      end

      private

      # The default branch moved since the ladder ran out: start it again.
      #
      # @return [void]
      def renew(ordinal, target)
        @mutex.synchronize do
          held = @tallies[ordinal]&.held_at
          @tallies.delete(ordinal) if held && held != target
        end
      end

      # @param resolved_by [String, nil] who resolved the last conflict, on success
      # @param why [String, nil] why it failed, otherwise
      # @param refresh [OpenLanes::Vcs::Refresh, nil] aborted on failure
      # @return [OpenLanes::Execution::Executor::Result]
      def finish(ordinal, spent, resolved_by: nil, base: nil, stops: 1, why: nil, refresh: nil)
        if resolved_by
          @mutex.synchronize { @tallies.delete(ordinal) }
          note = "rebased onto #{base}; #{resolved_by} resolved #{stops} conflicted commit#{"s" unless stops == 1}; " \
                 "plan work resumes next run"
          UI.log("rebase: #{note}", plan: ordinal)
          return result(spent, passed: true, note:)
        end

        aborted = refresh&.abort!(why.to_s)
        result(spent, passed: false, note: failed(ordinal, aborted&.base || "the default branch", aborted&.target, why))
      end

      # One more failure on the tally, and the line that says what comes next.
      #
      # @return [String]
      def failed(ordinal, base, target, why)
        tally = @mutex.synchronize do
          failures = @tallies.fetch(ordinal) { Tally.new(failures: 0, held_at: nil) }.failures + 1
          @tallies[ordinal] = Tally.new(failures:, held_at: failures >= LADDER.size ? target : nil)
        end
        nxt = if tally.held_at
                "REBASE PENDING: retries exhausted; the plan works on its old base until #{base} moves"
              else
                step = LADDER[tally.failures]
                "#{RESOLVER} retries on a later run as #{step.values.join("/")}"
              end
        note = "rebase onto #{base} aborted, branch restored (#{why}); #{nxt}"
        UI.log("rebase: #{note}", plan: ordinal)
        note
      end

      # @param spent [Array<OpenLanes::Execution::Executor::Result>]
      # @return [OpenLanes::Execution::Executor::Result]
      def result(spent, passed:, note:)
        sum = ->(field) { spent.sum { it.respond_to?(field) ? it.public_send(field).to_i : 0 } }
        Execution::Executor::Result.new(ok: passed,
          note:,
          up: sum.call(:up),
          down: sum.call(:down),
          subagents: sum.call(:subagents),
          delegated: sum.call(:delegated),
          seconds: spent.sum { it.respond_to?(:seconds) ? it.seconds.to_f : 0.0 },
          cached: sum.call(:cached))
      end
    end
  end
end
