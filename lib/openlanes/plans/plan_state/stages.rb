# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # The harness's record of each agent's rounds, the state it last moved
      # the folder to, and the "resume anyway" window on a halt.
      class Stages < Section
        # @return [Array<Hash>]
        def stages = read["stages"]

        # Record or update one agent's round. A later call for the same agent
        # and round updates the latest record of it; +reset+ appends a new
        # record instead, because rounds are numbered per state and per run.
        #
        # @param agent [String]
        # @param round [Integer]
        # @param reset [Boolean] start a new record rather than update one
        # @param fields [Hash]
        # @return [Hash] the stage as written
        def stage!(agent, round, reset, fields)
          stage = nil
          update do |data|
            stage = data["stages"].rfind { |s| s["agent"] == agent && s["round"] == round } unless reset
            stage ||= { "agent" => agent, "round" => round }.tap { data["stages"] << it }
            stage.merge!(fields.transform_keys(&:to_s).compact)
            count(stage, data, fields)
          end
          stage
        end

        # @return [String, nil]
        def state = read["state"]

        # @param key [Symbol, String] the state the folder was just moved to
        # @return [void]
        def state!(key)
          update do |data|
            data["moves"] = data["moves"].to_i + 1 unless data["state"] == key.to_s
            data["state"] = key.to_s
          end
        end

        # @return [Integer] how many times {#state!} has moved the plan
        def moves = read["moves"].to_i

        # @return [Time, nil] until when a 💣 on this plan does not halt the run
        def resume_until
          text = read["resume_until"] or return nil
          parse_time(text)
        end

        # @param now [Time]
        # @return [Boolean] whether a halt on this plan is lifted right now
        def resumed?(now) = (resume_until || now) > now

        # @param till [Time] when the halt comes back
        # @return [Time] as written
        def resume_anyway!(till)
          update { |data| data["resume_until"] = till.iso8601 }
          till
        end

        private

        # A settling round notes how often the plan had moved by then, so
        # {Recovery#resumption} sees a move no stage recorded; a dispatch
        # names the visit it belongs to, so {Rounds} counts it in the right one.
        #
        # @return [void]
        def count(stage, data, fields)
          stage["moves"] = data["moves"].to_i if fields.key?(:to)
          stage["visit"] ||= data["moves"].to_i if fields.key?(:from)
        end
      end
    end
  end
end
