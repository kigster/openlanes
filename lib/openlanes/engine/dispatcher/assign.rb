# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Who works what next: the first agent that may take each plan
      # ({Candidates}) started, until every slot is full. When nothing can
      # start, it says what the run is waiting for ({IdleReason}), once.
      class Assign < Step
        # @param desk [Desk]
        # @param start [Start]
        # @param rescan [Integer] idle ticks between rescans while staying
        def initialize(desk, start:, rescan:)
          super(desk)
          @start = start
          @rescan = rescan
          @idle_ticks = 0
          @quota = Quota.new(desk)
          @idle_reason = IdleReason.new(desk)
          @candidates = Candidates.new(desk, quota: @quota, upkeep: Upkeep.new(desk), gate: QualityGate.new(desk))
        end

        # @!method next_dispatchable
        #   @return [Array(OpenLanes::Agents::Agent, OpenLanes::Plans::Subject), nil] see {Candidates}
        # @!method blockers_first(subjects)
        #   @return [Array<OpenLanes::Plans::Subject>] see {Candidates#blockers_first}
        def_delegators :@candidates, :next_dispatchable, :blockers_first

        # @param subjects [Array<OpenLanes::Plans::Subject>] the plans in scope
        # @return [String] what an idle run is waiting for
        def idle_reason(subjects) = @idle_reason.call(subjects)

        # @return [void]
        def dispatch
          @quota.ask_for_rounds
          refusals.clear
          started = 0
          while running.size < runner.jobs && (pair = next_dispatchable)
            outcome = claim_and_start(pair)
            break unless outcome

            started += 1 unless outcome == :skipped
          end
          settle_idle(started) if stay?
        end

        # Whether an idle staying run skips this tick's dispatch. Dispatching
        # reloads the tree and runs `resync dirs` over it, which is cheap once
        # but not twice a second for hours with nothing to find, so an idle
        # run looks again every {RESCAN} ticks, or at once when woken.
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

        private

        # Lost to another machine between the check and the claim, or Redis
        # cannot say who holds it (W31), or lost to an agent outside
        # openlanes: the rest of the pass goes on without the plan, which is
        # remembered so `next_dispatchable` does not hand it back. Lost the
        # lock file to another run here (false): the next tick steps around it.
        #
        # @return [true, false, :skipped]
        def claim_and_start(pair)
          unless runner.claim(pair.last)
            refusals << pair.last.feature.ordinal.to_s
            return :skipped
          end
          started = @start.start(*pair)
          started.nil? ? :skipped : started
        end

        # Idle when nothing else is under way, said once per change, so the
        # log reads as a story rather than a heartbeat.
        def settle_idle(started)
          self.idle = started.zero? && quiet?
          said = idle ? idle_reason(runner.in_scope) : nil
          UI.log(said) if said && said != @said
          @said = said
        end
      end
    end
  end
end
