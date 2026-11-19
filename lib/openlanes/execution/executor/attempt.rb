# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # One invocation, as every step of running it needs it: which agent on
      # which plan, in which checkout, on which CLI, writing which trace,
      # under which handle, metered by which sessions, against which clock.
      # The steps used to take these eight one keyword at a time, which is
      # what put {Executor#call} at nine parameters.
      #
      # The clock starts after the process does, so an attempt is first
      # built without one and given it with `with(clock:)`.
      #
      # @!attribute [r] agent
      #   @return [OpenLanes::Agents::Agent]
      # @!attribute [r] subject
      #   @return [OpenLanes::Plans::Subject]
      # @!attribute [r] root
      #   @return [String] the checkout the agent runs in
      # @!attribute [r] profile
      #   @return [OpenLanes::Agents::Profile]
      # @!attribute [r] trace
      #   @return [String] the raw NDJSON trace
      # @!attribute [r] handle
      #   @return [OpenLanes::Execution::Executor::Handle]
      # @!attribute [r] sessions
      #   @return [OpenLanes::Execution::Executor::Sessions]
      # @!attribute [r] clock
      #   @return [OpenLanes::Execution::Clock, nil]
      Attempt = Data.define(:agent, :subject, :root, :profile, :trace, :handle, :sessions, :clock) do
        def initialize(clock: nil, **) = super

        # @return [String] the plan's number, as the log names it
        def plan = subject.feature.ordinal.to_s
      end
    end
  end
end
