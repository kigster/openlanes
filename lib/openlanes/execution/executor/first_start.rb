# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # One invocation from its first start to its verdict: the boundary
      # snapshot, the control file, the argv, the clock, supervision, and the
      # journal record of what the session it ended in holds.
      class FirstStart
        # @param crew [OpenLanes::Execution::Executor::Crew]
        def initialize(crew) = @crew = crew

        # @param attempt [OpenLanes::Execution::Executor::Attempt] not yet started
        # @param request [OpenLanes::Execution::Executor::Request]
        # @param started [Float] UI.monotonic when it was asked for
        # @return [OpenLanes::Execution::Executor::Result]
        def call(attempt, request, started, &)
          before = Boundary.snapshot(attempt.root)
          request = prepared(attempt, request)
          argv = @crew.invocations.first(attempt, request)
          # After the prompt, which is cut to what the resumed session lacks.
          JournalHold.forget(attempt.agent, attempt.subject) if request.resume
          status, timed = supervised(attempt, request, argv, before, &)
          JournalHold.hold(attempt) unless request.rebase
          @crew.verdict.judge(timed, status, before:, started:)
        end

        private

        # @return [OpenLanes::Execution::Executor::Request] with its control file, and no
        #   session to resume on a CLI that cannot
        def prepared(attempt, request)
          request.with(control: register(attempt), resume: (request.resume if attempt.profile.adapter.resumes?))
        end

        # @return [Array(Process::Status, OpenLanes::Execution::Executor::Attempt)] how it
        #   ended, and the attempt with its clock
        def supervised(attempt, request, argv, before, &)
          child = @crew.launcher.launch(argv, attempt, &)
          timed = arm(attempt, before)
          [@crew.supervision.supervise(child, timed, restarts(attempt, request, argv, &), &), timed]
        end

        # @return [String] the control file, registered and handed to the handle
        def register(attempt)
          handle = attempt.handle
          name = attempt.agent.name
          handle.trace = attempt.trace
          handle.control = Control.register(@crew.trace_dir, "#{attempt.plan}-#{name}")
          handle.label = AgentProcess::Label.new(plan: attempt.plan, agent: name, control: handle.control)
          handle.control
        end

        # @return [OpenLanes::Execution::Executor::Attempt] with its clock running
        def arm(attempt, before)
          handle = attempt.handle
          clock = @crew.launcher.start_clock(handle, seconds: @crew.preferences.timeout_for(attempt.agent))
          handle.restart!(cwd: attempt.root,
            trace: attempt.trace,
            control: handle.control,
            before: before.to_h,
            deadline: Executor.deadline(clock))
          attempt.with(clock:)
        end

        # A fresh start for a session that turned out to be gone, and what a
        # throttled start is started with again: the same argv when it carries
        # a session on, which keeps its id, and a fresh one otherwise.
        #
        # @return [OpenLanes::Execution::Executor::Restarts]
        def restarts(attempt, request, argv, &)
          launcher = @crew.launcher
          relaunch = lambda do
            attempt.handle.session = nil
            launcher.launch(@crew.invocations.first(reprofiled(attempt), request.with(resume: nil)), attempt, &)
          end
          Restarts.new(resume: request.resume, relaunch:, again: request.resume ? -> { launcher.launch(argv, attempt, &) } : relaunch)
        end

        # A fresh start's argv is built from the profile as it is now, not as
        # it was when the round began: a relaunch can come minutes later, after
        # a rate-limit wait in which a person picked another model with
        # `prefer_model`. Only the argv changes; the attempt launched stays the
        # one the round started with, as it was before the executor was split.
        #
        # @return [OpenLanes::Execution::Executor::Attempt]
        def reprofiled(attempt)
          attempt.with(profile: @crew.preferences.profile_for(attempt.agent, attempt.subject, root: attempt.root))
        end
      end
    end
  end
end
