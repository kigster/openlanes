# frozen_string_literal: true

module OpenLanes
  module Engine
    class Extensions
      # What happens when a running agent's clock runs low (E2): four steps
      # that need no person, then the person. The agent works through all
      # of it; nothing here stops one because a decision is still out.
      #
      # 1. The engine adds the agent's `extension_cap` on its own, all at
      #    once. The clock only limits, so an agent that finishes early
      #    gives the rest back by ending; and every smaller step would have
      #    told it "5 minutes left" again and had it wrap up again.
      # 2. When that runs low too, the agent itself is asked how much more
      #    it needs: {Execution::Control::ESTIMATE} in its control file,
      #    answered with `openlanes state estimate`. Once a round.
      # 3. An estimate within `extension_cap` is granted as asked.
      # 4. A larger one goes to the arbitrator ({Arbitration::Overtime}),
      #    which may grant up to `extension_ceiling` or decline.
      # 5. No estimate in {REPLY_WITHIN}, no ruling in {RULING_WITHIN}, a
      #    decline, or an answer that could not be read: the request becomes
      #    a person's card, as E1 has it, and the clock runs out as it
      #    always did.
      #
      # While 2 to 4 are out the clock is held near {HOLD_AT}, so the agent is
      # told neither WRAP_UP nor STOP for a wait that is not its own. The
      # hold is bounded by the two deadlines, both counted on the wall clock
      # from times kept in `state.json`: a decision that never comes holds a
      # clock for fifteen minutes at most, across restarts too.
      #
      # Every step is a request in the plan's `state.json` before it is a
      # move of the clock ({Round}), and each is read back from there, so a
      # restarted engine neither grants twice nor asks twice.
      class Ladder
        # Seconds a clock is held at while a decision is out: above the
        # WRAP_UP at 60, with room for a slow tick.
        HOLD_AT = 180

        # Seconds a held clock may fall below {HOLD_AT} before it is raised
        # again. Raising it on every tick wrote the new deadline into the
        # run's state file twice a second for as long as a decision was out.
        HOLD_STEP = 30

        # Seconds an agent has to say how much it needs. It reads its
        # control file between steps, and a step can be a long test run.
        REPLY_WITHIN = 300

        # Seconds the arbitrator has to rule on a request, its unreadable
        # answers and their back-off included.
        RULING_WITHIN = 600

        # A request's `stage`, in the order it may pass through them.
        ESTIMATE = "estimate"
        ARBITRATION = "arbitration"
        PERSON = "person"

        # Who granted time on the agent's own estimate, as `by:` says it.
        ESTIMATED = "estimate"

        # @param extensions [OpenLanes::Engine::Extensions] asks the person, and says whether to grant unasked
        # @param overtime [#call] gives the run's {Arbitration::Overtime}, or nil when it has no arbitrator
        def initialize(extensions:, overtime: -> {})
          @extensions = extensions
          @overtime = overtime
          @open = {}
        end

        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [Boolean] whether the job is worth a read of its plan this
        #   tick: its clock is low, or a decision about it is out
        def due?(job)
          left = job.handle.remaining
          @open.key?(job.key) || (!left.nil? && left <= ASK_AT)
        end

        # @param job [OpenLanes::Engine::Dispatcher::Job] a round that ended
        # @return [void]
        def forget(job) = @open.delete(job.key)

        # One step, at most, for one running job.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @param subject [OpenLanes::Plans::Subject] its plan, read fresh
        # @return [Hash, nil] the request as granted, when time reached the clock on this tick
        def watch(job, subject)
          round = Round.new(job:, subject:, at: @extensions.now)
          request = round.pending
          return start(round) unless request

          # Remembered, so the request is still read once its held clock
          # is no longer low; found again here after a restart.
          @open[job.key] = true if [ESTIMATE, ARBITRATION].include?(request["stage"])
          advance(round, request)
        end

        private

        # @return [Hash, nil]
        def start(round)
          forget(round.job)
          return person(round) unless @extensions.automatic?

          spare = round.agent.extension_cap - round.auto_granted
          # Step 1, written settled in one write.
          return round.reach(round.request!(by: AUTO, grant: "live", seconds: spare)) if spare.positive?

          round.staged? ? person(round) : ask(round)
        end

        # Step 5 for a round the ladder has nothing more for: E1's card.
        def person(round)
          @extensions.ask_time(round.subject.feature.path, **round.naming)
          nil
        end

        # Step 2.
        def ask(round)
          request = round.request!(stage: ESTIMATE)
          return escalate(round, request, "its clock had stopped before it could be asked") unless round.handle.say!(Brief.question(round))

          @open[round.job.key] = true
          hold(round)
        end

        # @return [Hash, nil]
        def advance(round, request)
          case request["stage"]
          when ESTIMATE then estimated(round, request)
          when ARBITRATION then ruled(round, request)
          end
        end

        # Steps 3 and 4.
        def estimated(round, request)
          seconds = request["estimate"] or return wait(round, request, REPLY_WITHIN, "no estimate from #{round.agent.name}")
          return grant(round, request, seconds:, by: ESTIMATED) if seconds <= round.agent.extension_cap

          round.stage!(request, ARBITRATION)
          hold(round)
        end

        # Step 4's answer. The arbitrator's grant is bounded here, not
        # trusted: it reads a brief, and a typo of 600 for 60 would be ten hours.
        def ruled(round, request)
          ruling = ruling_on(round, request)
          return wait(round, request, RULING_WITHIN, "the arbitrator did not rule in time") if ruling.nil?
          return escalate(round, request, ruling) if ruling.is_a?(String)

          seconds = [ruling.seconds, round.agent.extension_ceiling].min
          grant(round, request, seconds:, by: OpenLanes::Arbitration::AGENT, reason: ruling.reason)
        end

        # @return [OpenLanes::Arbitration::TimeRuling, String, nil] a grant;
        #   why it is a person's now; nil while the arbitrator is out
        def ruling_on(round, request)
          overtime = @overtime.call or return "this run has no arbitrator"
          ruling = overtime.verdict(round.subject, request["number"]) { Brief.for(round, request) }
          return ruling if ruling.nil? || (ruling.respond_to?(:granted?) && ruling.granted?)

          ruling == Arbitration::Overtime::GIVEN_UP ? "the arbitrator's answer could not be read" : "the arbitrator declined: #{ruling.reason}"
        end

        # Still inside the stage's deadline: hold the clock. Past it: step 5.
        def wait(round, request, limit, why)
          since = Time.iso8601(request["staged_at"] || request["asked_at"])
          round.at - since < limit ? hold(round) : escalate(round, request, why)
        end

        # @return [nil]
        def hold(round)
          round.handle.hold!(HOLD_AT) if round.handle.remaining.to_i <= HOLD_AT - HOLD_STEP
          nil
        end

        # Step 5: the request becomes a person's, and the agent's file stops
        # asking a question nobody is waiting on any more.
        def escalate(round, request, why)
          round.stage!(request, PERSON, note: why)
          round.handle.say!("#{Execution::Control::WARN}: #{Brief.minutes(round.handle.remaining)} minutes left")
          forget(round.job)
          UI.log("#{round.agent.name} needs more time, and a person decides: #{why}",
            level: :warn,
            plan:  round.subject.feature.ordinal.to_s)
          nil
        end

        # @param terms [Hash] `seconds:`, `by:`, and the arbitrator's `reason:`
        # @return [Hash, nil] nil when somebody settled it first
        def grant(round, request, **terms)
          forget(round.job)
          settled = round.settle!(request, **terms)
          settled && round.reach(settled)
        end
      end
    end
  end
end
