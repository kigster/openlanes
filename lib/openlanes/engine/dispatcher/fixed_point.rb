# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Whether a run has reached its end: nothing running and nothing left to
      # start. A staying run (the engine with its control room) never ends on
      # its own, not even once every plan is {FINISHED}: the page can create
      # the next plan at any moment. Only a quit ends it, once the agents
      # have gone.
      class FixedPoint
        # @param desk [Desk]
        # @param assign [Assign] asked what could still be started
        def initialize(desk, assign)
          @desk = desk
          @assign = assign
        end

        # @return [Boolean]
        def reached?
          return false unless @desk.quiet?
          # A quit does not wait for a look: it only reads, and the coverage
          # run under it is a child process killed at exit.
          return true if Execution::Control.quit?
          return false if @desk.stay? || looking?

          @assign.next_dispatchable.nil?
        end

        private

        # An ending run does not return in the middle of a look: what it
        # finds is acted on, on the next tick, before the run reports.
        def looking?
          runner = @desk.runner
          runner.verification&.busy? || runner.arbitration&.busy? || false
        end
      end
    end
  end
end
