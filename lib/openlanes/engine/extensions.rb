# frozen_string_literal: true

require "time"

module OpenLanes
  module Engine
    # An agent that runs out of time or rounds asks for more instead of
    # simply ending (E1). The harness, not the agent, asks: a question on the
    # plan, `X<n>`, with three fixed choices, kept in the plan's `state.json`
    # so it survives a restart and can be answered from any control room.
    #
    # - Time: asked while the agent still runs, {ASK_AT} seconds before its
    #   clock's zero. A time choice answered then moves the live deadline, and
    #   the agent carries on in the same session.
    # - Rounds: asked once the agent has used every round it had on the plan's
    #   state without finishing. Every choice gives it one more round; the
    #   time choices also lengthen that round's clock.
    #
    # Nobody may be watching, so each kind is granted once without an answer:
    # ten more minutes when the clock reaches {AUTO_AT}, and one more round at
    # once on a run with no control room, or {AUTO_AFTER} seconds after asking
    # on one that has one. After that the request waits for a person, and the
    # limit applies as it always did: STOP at zero, no round past the last.
    #
    # Nothing here starts, stops or renames anything; the dispatcher asks and
    # acts on the answers.
    class Extensions
      # Seconds left on a clock when the time request is asked: the same
      # moment the agent itself is told "5 minutes left".
      ASK_AT = 300

      # Seconds left when an unanswered time request is granted on its own:
      # before the clock's WRAP_UP at 60, so the agent is not already
      # wrapping up when the time arrives.
      AUTO_AT = 120

      # Seconds a rounds request waits for a person on a staying run before
      # it is granted on its own.
      AUTO_AFTER = 300

      # Who answered a request nobody else did.
      AUTO = "auto"

      # One of the three choices every request offers.
      #
      # @!attribute [r] letter
      #   @return [String]
      # @!attribute [r] label
      #   @return [String]
      # @!attribute [r] seconds
      #   @return [Integer] extra seconds on the clock, 0 for a round alone
      Choice = Data.define(:letter, :label, :seconds)

      # @return [Array<Choice>]
      CHOICES = [
        Choice.new(letter: "a", label: "Extend Rounds by 1", seconds: 0),
        Choice.new(letter: "b", label: "Extend Time by 10 minutes", seconds: 600),
        Choice.new(letter: "c", label: "Extend Time by 20 minutes", seconds: 1200)
      ].freeze

      # The choice granted without an answer, by what ran out.
      DEFAULTS = { "time" => "b", "rounds" => "a" }.freeze

      # @param stay [Boolean] whether a control room can answer at all
      # @param auto [Boolean] false to ask and never grant on its own
      # @param now [Proc] the wall clock
      def initialize(stay:, auto: true, now: -> { Clock::System.now })
        @stay = stay
        @auto = auto
        @now = now
        # Rounds used are counted in memory, from this run's start; rounds
        # granted are counted from the same moment, or a restart would hand
        # back every round ever granted on top of a fresh allowance.
        @since = now.call
      end

      # A running agent whose clock is nearly out: ask once per round, and
      # grant ten minutes on its own once per agent and state.
      #
      # @param job [#task, #state, #handle] the dispatcher's job
      # @param path [String] the plan folder as it is named now
      # @return [Hash, nil] the request, when there is one
      def watch(job, path)
        left = job.handle.remaining or return nil
        return nil if left > ASK_AT

        plan = Plans::PlanState.for(path)
        agent = job.task.agent.name
        state = job.state.to_s
        request = pending(plan.extensions, agent, state) ||
                  unless asked?(plan.extensions, agent, state, job.task.round, "time")
                    plan.ask_extension!(agent:, state:, round: job.task.round, limit: "time", at: @now.call)
                  end
        return request unless @auto && request && left <= AUTO_AT && !auto?(plan.extensions, agent, state, "live")

        answer!(path, request["number"], DEFAULTS.fetch("time"), by: AUTO, live: job.handle)
      end

      # An agent with no rounds left on the plan's state: ask once per
      # exhaustion, and grant a round on its own once per agent and state.
      #
      # @param path [String]
      # @param agent [String]
      # @param state [#to_s] the status key
      # @param round [Integer] the last round it ran
      # @return [Hash, nil] the request, when there is one
      def exhausted(path, agent, state, round)
        plan = Plans::PlanState.for(path)
        state = state.to_s
        all = plan.extensions
        request = pending(all, agent, state) ||
                  unless asked?(all, agent, state, round, "rounds")
                    plan.ask_extension!(agent:, state:, round:, limit: "rounds", at: @now.call)
                  end
        return request unless @auto && request && !auto?(all, agent, state, "round") && waited?(request)

        answer!(path, request["number"], DEFAULTS.fetch("rounds"), by: AUTO)
      end

      # Settle a request with a choice. A time choice reaches a clock still
      # running when +live+ is given; anything else is one more round, with
      # the choice's seconds added to that round's clock.
      #
      # @param path [String]
      # @param number [Integer]
      # @param letter [String] "a", "b" or "c"
      # @param by [String]
      # @param live [OpenLanes::Execution::Executor::Handle, nil] the asking agent's, while it runs
      # @return [Hash, nil] the request as settled; nil when it was settled already
      # @raise [ArgumentError] on a letter that is not one of {CHOICES}
      def answer!(path, number, letter, by:, live: nil)
        choice = CHOICES.find { it.letter == letter.to_s.downcase } or
          raise ArgumentError, "#{letter} is not one of #{CHOICES.map { "#{it.letter})" }.join(", ")}"
        plan = Plans::PlanState.for(path)
        request = plan.extensions.find { it["number"] == Integer(number) }
        return nil if request.nil? || request.key?("settled_at")

        # Only a time request moves a running clock: every choice on a
        # rounds request is a round, even while the agent was resumed.
        grant = live && request["limit"] == "time" && choice.seconds.positive? ? "live" : "round"
        settled = plan.settle_extension!(number, answer: choice.letter, by:, grant:, seconds: choice.seconds, at: @now.call)
        # Someone else settled it between the read above and this write.
        return nil unless settled

        # The clock told the agent STOP, or stopped, before the time got
        # there: the time comes with a round instead of going nowhere.
        settled = plan.amend_extension!(number, grant: "round") if grant == "live" && !live.extend!(choice.seconds)
        UI.log("#{by == AUTO ? "auto-extended" : "extended by #{by}"}: #{request["agent"]} #{choice.label.downcase}",
          plan: File.basename(path)[/\A\d{3}\.\d{2}/])
        settled
      end

      # The rounds a person or this class has added to an agent's own.
      #
      # @param path [String]
      # @param agent [String]
      # @param state [#to_s]
      # @return [Integer]
      def rounds(path, agent, state)
        granted(Plans::PlanState.for(path).extensions, agent, state.to_s).count { Time.iso8601(it["settled_at"]) >= @since.floor }
      end

      # The extra seconds a granted round runs on, handed out once.
      #
      # @param path [String]
      # @param agent [String]
      # @param state [#to_s]
      # @return [Integer] 0 when the round has none
      def take_seconds(path, agent, state)
        plan = Plans::PlanState.for(path)
        grant = granted(plan.extensions, agent, state.to_s).find { it["seconds"].to_i.positive? && !it["spent"] }
        return 0 unless grant

        plan.spend_extension!(grant["number"])
        grant["seconds"]
      end

      # A request nobody needs any more: the agent's round ended, however it
      # ended. A time card left open would say "running out of time" about an
      # agent no longer running, and stand in for the next round's own ask.
      #
      # @param path [String]
      # @param agent [String]
      # @param state [#to_s]
      # @return [void]
      def close!(path, agent, state, why: "finished")
        plan = Plans::PlanState.for(path)
        request = pending(plan.extensions, agent, state.to_s) or return
        plan.settle_extension!(request["number"], closed: why, at: @now.call)
      end

      class << self
        # The requests a plan still has open for its state, as the page's
        # `Question`s, beside the ones `blocked.md` asks.
        #
        # @param subject [OpenLanes::Plans::Subject]
        # @param plan [OpenLanes::Plans::PlanState]
        # @return [Array<Hash>]
        def questions(subject, plan)
          state = subject.status.key.to_s
          plan.extensions.reject { it.key?("settled_at") || it["state"] != state }.map { question(subject, it) }
        end

        private

        # @return [Hash]
        def question(subject, request)
          time = request["limit"] == "time"
          recommended = DEFAULTS.fetch(request["limit"])
          { id:       "#{subject.feature.ordinal}/X#{request["number"]}",
            number:   request["number"],
            kind:     "extension",
            heading:  time ? "#{request["agent"]} is running out of time" : "#{request["agent"]} is out of rounds",
            body:     body(subject, request, time),
            agent:    request["agent"],
            owner:    "technical",
            options:  CHOICES.map do |choice|
              { letter:      choice.letter,
                label:       choice.label,
                recommended: choice.letter == recommended,
                answer:      "#{choice.letter}) #{choice.label}" }
            end,
            held:     false,
            asked_at: request["asked_at"] }
        end

        # @return [String]
        def body(subject, request, time)
          if time
            "Round #{request["round"]} on #{subject.status} has under #{ASK_AT / 60} minutes left on its clock. " \
              "More time lets it carry on where it is; another round starts it again from its resume note."
          else
            "It has used every round it had on #{subject.status} without finishing. " \
              "Each choice gives it one more round; the time choices also lengthen that round's clock."
          end
        end
      end

      private

      # @return [Hash, nil] the agent's unsettled request on this state
      def pending(all, agent, state) = all.find { it["agent"] == agent && it["state"] == state && !it.key?("settled_at") }

      # @return [Array<Hash>] the requests that gave the agent a round on this state
      def granted(all, agent, state) = all.select { it["grant"] == "round" && it["agent"] == agent && it["state"] == state }

      # A time request answered with time on the running clock does not
      # count: when that time runs low too, the round asks again, so a
      # person can add to an automatic grant.
      #
      # @return [Boolean] whether this round already asked about this limit
      def asked?(all, agent, state, round, limit)
        all.any? do |r|
          r["agent"] == agent && r["state"] == state && r["round"] == round && r["limit"] == limit && r["grant"] != "live"
        end
      end

      # @return [Boolean] whether the one grant of this kind nobody answered is spent
      def auto?(all, agent, state, grant)
        all.any? { it["agent"] == agent && it["state"] == state && it["by"] == AUTO && it["grant"] == grant }
      end

      # @return [Boolean] whether a rounds request has waited long enough for a person
      def waited?(request)
        return true unless @stay

        @now.call - Time.iso8601(request["asked_at"]) >= AUTO_AFTER
      end
    end
  end
end
