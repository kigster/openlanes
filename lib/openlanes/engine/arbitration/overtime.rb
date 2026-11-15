# frozen_string_literal: true

module OpenLanes
  module Engine
    class Arbitration
      # The arbitrator asked whether a running agent may have more time
      # than the engine grants on the agent's own word (E2).
      #
      # The same agent, the same {Asker} and the same {Retries} as a ruling,
      # run the same way: off the loop's thread, the answer picked up on a
      # later tick, an unreadable one backed off and then given up on. What
      # differs is the plan: an agent is running on it, so it is neither
      # fenced off nor moved, and each request gets a thread of its own
      # rather than a turn behind a ruling that may take ten minutes while
      # the asking agent's clock is held.
      #
      # Nothing is written to `state.json` here: the caller records the
      # grant on the request that asked.
      class Overtime
        # What gave the arbitrator up on a request, as {#verdict} says it.
        GIVEN_UP = :given_up

        # @param agents [OpenLanes::Agents::Registry]
        # @param ask [#call] given the agent, the plan and the brief, returns the final answer
        # @param retries [Retries]
        def initialize(agents:, ask:, retries:)
          @agents = agents
          @ask = ask
          @retries = retries
          @threads = {}
        end

        # Asked once a tick while a request waits on the arbitrator. Starts
        # the question when none is under way and none is backing off, and
        # hands the answer back once, on the first tick after it came.
        #
        # @param subject [OpenLanes::Plans::Subject] the plan as it stands now
        # @param number [Integer] the request's `X<n>`
        # @yieldreturn [String] what the arbitrator is told, built only when it is asked
        # @return [OpenLanes::Arbitration::TimeRuling, Symbol, nil] the ruling;
        #   {GIVEN_UP} when it cannot be asked or read; nil while there is nothing yet
        def verdict(subject, number)
          key = [subject.feature.ordinal.to_s, ["extension", number]]
          agent = @agents.find(OpenLanes::Arbitration::AGENT)
          return GIVEN_UP if agent.nil? || @retries.given_up?(key)
          return collect(key) if @threads[key] && !@threads[key].alive?

          @threads[key] ||= start(agent, subject, yield) unless @retries.backing_off?(key)
          nil
        end

        # @return [void] waits for every question under way
        def join = @threads.each_value(&:join)

        private

        # On a thread of its own. Everything is caught and returned, so
        # `#value` never raises into the loop.
        #
        # @return [Thread]
        def start(agent, subject, brief)
          Thread.new do
            Thread.current.report_on_exception = false
            OpenLanes::Arbitration.time_ruling(@ask.call(agent, subject, brief))
          rescue StandardError => e
            e
          end
        end

        # @return [OpenLanes::Arbitration::TimeRuling, Symbol, nil]
        def collect(key)
          answer = @threads.delete(key).value
          return answer.tap { @retries.clear(key) } unless answer.is_a?(StandardError)

          count = @retries.failed!(key)
          UI.log("arbitration refused: #{answer.message} (attempt #{count} of #{ATTEMPTS})", level: :warn, plan: key.first)
          GIVEN_UP if @retries.given_up?(key)
        end
      end
    end
  end
end
