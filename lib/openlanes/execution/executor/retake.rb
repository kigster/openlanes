# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # An agent an earlier engine started and did not see end, taken back
      # (B1 in plan 041): its transcript is rebuilt from the agent's whole
      # output (B7), its clock runs out at the deadline it was given, and it
      # is judged as a first start is, against the snapshot taken before it ran.
      class Retake
        # @param crew [OpenLanes::Execution::Executor::Crew]
        def initialize(crew) = @crew = crew

        # @param attempt [OpenLanes::Execution::Executor::Attempt] in the checkout it ran in
        # @param restart [Hash{String => Object}] what {Handle#restart!} was told
        # @param started [Float] UI.monotonic when it was asked for
        # @return [OpenLanes::Execution::Executor::Result]
        def call(attempt, restart, started, &)
          adopt(attempt, restart)
          child = @crew.launcher.follow(AgentProcess.attach(restart.fetch("process")), attempt, &)
          timed = rearm(attempt, restart)
          status = @crew.supervision.supervise(child, timed, &)
          before = Boundary::Snapshot.new(**restart.fetch("before").transform_keys(&:to_sym))
          @crew.verdict.judge(timed, status, before:, started:)
        end

        private

        # The trace read again from the start, and the control file taken back.
        #
        # @return [void]
        def adopt(attempt, restart)
          handle = attempt.handle
          File.write(attempt.trace, "")
          handle.trace = attempt.trace
          handle.control = Control.adopt(restart.fetch("control"))
          handle.label = AgentProcess::Label.new(plan: attempt.plan, agent: attempt.agent.name, control: handle.control)
        end

        # The deadline as this engine armed it, so a third engine does not
        # charge the agent again for time this one forgave.
        #
        # @return [OpenLanes::Execution::Executor::Attempt] with its clock running
        def rearm(attempt, restart)
          launcher = @crew.launcher
          seconds = launcher.rearm(attempt.agent, restart, budget: @crew.preferences.timeout_for(attempt.agent))
          clock = launcher.start_clock(attempt.handle, seconds:)
          attempt.handle.restart!(deadline: Executor.deadline(clock))
          attempt.with(clock:)
        end
      end
    end
  end
end
