# frozen_string_literal: true

module OpenLanes
  module Engine
    class Extensions
      # One running round as the {Ladder} reads and writes it: the job, its
      # plan's `state.json`, and what that file holds about this round's
      # time. Built afresh each tick and read once, so a tick decides on one
      # picture of the file rather than on several.
      #
      # A round is named by its agent, the plan's state, its number and the
      # plan's moves: round numbers start again on each visit to a state,
      # and a grant made on an earlier visit must not count against this one.
      #
      # Every grant is written before the clock moves. A crash between the
      # two loses the time and never grants it twice.
      class Round
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @param subject [OpenLanes::Plans::Subject] the plan as it is named now
        # @param at [Time] the wall clock this tick, which stamps what it writes
        def initialize(job:, subject:, at:)
          @job = job
          @subject = subject
          @at = at
        end

        # @return [OpenLanes::Engine::Dispatcher::Job]
        attr_reader :job

        # @return [OpenLanes::Plans::Subject]
        attr_reader :subject

        # @return [Time]
        attr_reader :at

        # @return [OpenLanes::Plans::PlanState]
        def plan = @plan ||= Plans::PlanState.for(subject.feature.path)

        # @return [OpenLanes::Agents::Agent]
        def agent = job.task.agent

        # @return [OpenLanes::Execution::Executor::Handle]
        def handle = job.handle

        # @return [Hash] what names this round in a request
        def naming = { agent: agent.name, state: job.state.to_s, round: job.task.round }

        # @return [Hash, nil] the agent's unsettled request on this state
        def pending
          all.find { it["agent"] == agent.name && it["state"] == job.state.to_s && !it.key?("settled_at") }
        end

        # Every `auto` grant counts, the ones that became a round because
        # the clock had stopped included: counting only what reached a clock
        # would grant the same time again on the next tick.
        #
        # @return [Integer] seconds the engine has added to this round on its own
        def auto_granted = own.select { it["by"] == AUTO }.sum { it["seconds"].to_i }

        # @return [Boolean] whether this round's one question to its agent was asked
        def staged? = own.any? { it.key?("stage") }

        # A new request for this round's time.
        #
        # @param fields [Hash] `stage`, or the `by`, `grant` and `seconds` of a grant made outright
        # @return [Hash] the request as written
        def request!(**fields)
          settled = fields.key?(:grant) ? { settled_at: at.iso8601 } : {}
          plan.ask_extension!(**naming, limit: "time", at:, **fields, **settled)
        end

        # A request moved to its next stage, the stage's clock started.
        #
        # @param request [Hash]
        # @param stage [String]
        # @param note [String, nil] why, when it goes to a person
        # @return [Hash, nil] the request as it now stands
        def stage!(request, stage, note: nil)
          plan.amend_extension!(request["number"], **{ stage:, staged_at: at.iso8601, note: }.compact)
        end

        # A request settled with time for the running clock.
        #
        # @param request [Hash]
        # @param seconds [Integer]
        # @param by [String]
        # @param reason [String, nil] the arbitrator's
        # @return [Hash, nil] nil when somebody settled it first
        def settle!(request, seconds:, by:, reason: nil)
          plan.settle_extension!(request["number"], by:, grant: "live", seconds:, reason:, at:)
        end

        # The granted time put on the running clock. One the clock refuses,
        # because it told the agent STOP before the time got there, comes
        # with a round instead of going nowhere, as a person's answer does.
        #
        # @param granted [Hash] a settled request
        # @return [Hash, nil] the grant, when it reached the running clock
        def reach(granted)
          by, seconds = granted.values_at("by", "seconds")
          UI.log("#{by == AUTO ? "auto-extended" : "extended by #{by}"}: #{agent.name} #{Brief.minutes(seconds)} more minutes",
            plan: subject.feature.ordinal.to_s)
          return granted if handle.extend!(seconds)

          plan.amend_extension!(granted["number"], grant: "round")
          nil
        end

        private

        # @return [Array<Hash>] the plan's requests, read once
        def all = @all ||= plan.extensions

        # @return [Array<Hash>] this round's time requests on this visit
        def own
          wanted = naming.transform_keys(&:to_s).merge("limit" => "time", "moves" => plan.moves)
          all.select { |request| wanted.all? { |key, value| request[key] == value } }
        end
      end
    end
  end
end
