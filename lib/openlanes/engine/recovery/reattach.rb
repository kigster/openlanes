# frozen_string_literal: true

module OpenLanes
  module Engine
    module Recovery
      # The agents a dead engine left that a new one can take back (B1 and
      # B6 in plan 041): a Started stage of the dead run whose agent
      # supervisor is still running, or ended while no engine ran and left
      # its status behind. What it finds, the dispatcher adopts; the rest of
      # the dead run's stages are {Stranded}.
      #
      # Running means its PID file names the pid the stage recorded and
      # {Supervision::Probe} confirms it, so a reused pid is never taken for
      # an agent.
      class Reattach
        # One agent to take back.
        #
        # @!attribute [r] subject
        #   @return [Plans::Subject]
        # @!attribute [r] agent
        #   @return [Agents::Agent]
        # @!attribute [r] round
        #   @return [Integer]
        # @!attribute [r] from
        #   @return [Symbol] the state the plan showed when the agent was picked
        # @!attribute [r] restart
        #   @return [Hash{String => Object}] what {Execution::Executor::Handle#restart!} was told
        Found = Data.define(:subject, :agent, :round, :from, :restart) do
          # @return [Array(String, String, Integer)] the stage, as {Stranded} keys it
          def key = [subject.feature.ordinal.to_s, agent.name, round]
        end

        # What a stage must have recorded to be taken back.
        NEEDS = %w[process cwd trace control before deadline].freeze

        # @param runner [Runner]
        # @param state [StateFile]
        # @param probe [Supervision::Probe]
        def initialize(runner:, state:, probe: Supervision::Probe.new)
          @runner = runner
          @state = state
          @probe = probe
        end

        # @return [Array<Found>]
        def call
          @state.load
          @state.stranded.filter_map { |ordinal, stage| found(ordinal, stage) }
        end

        private

        # @param ordinal [String]
        # @param stage [Hash{String => Object}]
        # @return [Found, nil]
        def found(ordinal, stage)
          restart = stage["restart"]
          return nil unless recorded?(restart) && reachable?(restart["process"])

          subject = @runner.tree.reload.find(Plans::Ordinal.parse(ordinal)) or return nil
          agent = @runner.agents.find(stage["agent"]) or return nil
          return nil if @runner.foreign?(subject)

          Found.new(subject:, agent:, round: stage["round"], from: (stage["state"] || subject.status.key).to_sym, restart:)
        end

        # @param restart [Hash{String => Object}, nil]
        # @return [Boolean] whether everything {NEEDS} names was recorded
        def recorded?(restart) = !restart.nil? && NEEDS.all? { restart.key?(it) }

        # @param process [Hash{String => Object}]
        # @return [Boolean] still running, or ended with its status written
        def reachable?(process)
          File.exist?(process["status"].to_s) || running?(process)
        end

        # @param process [Hash{String => Object}]
        # @return [Boolean]
        def running?(process)
          file = Supervision::PidFile.parse(File.read(process["pid_file"].to_s))
          !file.nil? && file.pid == process["pid"] && @probe.verified?(file)
        rescue SystemCallError
          false
        end
      end
    end
  end
end
