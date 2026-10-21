# frozen_string_literal: true

require "json"

module OpenLanes
  module Engine
    class EventJournal
      # Rebuilds the in-flight picture from a journal file: the run, each
      # plan's last known state, and every agent that started and has not
      # ended, with its pid, session and last offset.
      #
      # A kill can tear the last line, so a line that does not parse is
      # counted in `torn` and skipped. A line whose `v` is newer than
      # {EventJournal::VERSION} is counted in `newer` rather than read, so an
      # old reader never invents a picture from fields it does not know.
      module Replay
        # One agent the journal says is running.
        Agent = Data.define(:plan, :agent, :round, :pid, :started_at, :session_id, :output_file, :offset)

        # What the journal says was going on when it stopped.
        #
        # @!attribute [r] run
        #   @return [Hash, nil] the `run_started` event, and `ended` when a `run_ended` followed
        # @!attribute [r] plans
        #   @return [Hash{String => String}] plan number to the last state a transition named
        # @!attribute [r] agents
        #   @return [Array<Agent>] agents started and not ended, in start order
        # @!attribute [r] torn
        #   @return [Integer] lines that did not parse
        # @!attribute [r] newer
        #   @return [Integer] lines from a newer schema version, skipped
        # @!attribute [r] seq
        #   @return [Integer] the last `seq` read
        InFlight = Data.define(:run, :plans, :agents, :torn, :newer, :seq) do
          # @return [Boolean] the run started and no `run_ended` followed
          def running? = !run.nil? && !run.key?("ended")
        end

        module_function

        # @param path [String] a journal file
        # @return [InFlight]
        def call(path)
          state = { run: nil, plans: {}, agents: {}, torn: 0, newer: 0, seq: 0 }
          File.foreach(path) { read(state, it) }
          InFlight.new(run: state[:run],
            plans: state[:plans],
            agents: state[:agents].values,
            torn: state[:torn],
            newer: state[:newer],
            seq: state[:seq])
        end

        # @api private
        def read(state, line)
          return if line.strip.empty?

          event = JSON.parse(line)
          return state[:newer] += 1 if event["v"].to_i > VERSION

          state[:seq] = event["seq"].to_i
          apply(state, event)
        rescue JSON::ParserError
          state[:torn] += 1
        end

        # @api private
        def apply(state, event)
          key = [event["plan"], event["agent"]]
          agents = state[:agents]
          case event["kind"]
          when "run_started" then state[:run] = event
          when "run_ended" then state[:run] = (state[:run] || {}).merge("ended" => event)
          when "transition" then state[:plans][event["plan"]] = event["to"]
          when "agent_started" then agents[key] = start(event)
          when "agent_session" then agents[key] &&= agents[key].with(session_id: event["session_id"])
          when "agent_offset" then agents[key] &&= agents[key].with(offset: event["offset"])
          when "agent_ended" then agents.delete(key)
          end
        end

        # @api private
        def start(event)
          Agent.new(plan: event["plan"],
            agent: event["agent"],
            round: event["round"],
            pid: event["pid"],
            started_at: event["started_at"],
            session_id: event["session_id"],
            output_file: event["output_file"],
            offset: 0)
        end
      end
    end
  end
end
