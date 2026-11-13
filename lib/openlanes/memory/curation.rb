# frozen_string_literal: true

module OpenLanes
  module Memory
    # One run of the curator over one plan: the agent reads the plan and
    # answers, and what its answer proposes goes through {Memory.propose}.
    #
    # The curator is granted no write tool, and this class does not trust
    # that either: only the lesson lines in its final answer are read, and
    # each passes {Inbox#add}'s checks or is dropped.
    class Curation
      # The agent that curates unless told otherwise.
      DEFAULT_AGENT = "curator"

      # What one plan yielded.
      #
      # @!attribute [r] ok
      #   @return [Boolean] whether the agent ran to the end
      # @!attribute [r] note
      #   @return [String] the executor's own word on the run
      # @!attribute [r] outcomes
      #   @return [Array<OpenLanes::Memory::Inbox::Outcome>]
      Report = Data.define(:ordinal, :ok, :note, :outcomes)

      # @param executor [#call] receives (agent, subject, root:, handle:)
      # @param agent [OpenLanes::Agents::Agent]
      # @param root [String] the project root, where the inbox is
      # @param answer [#call] reads an agent's final answer from its trace
      def initialize(executor:, agent:, root:, answer: Execution.method(:answer))
        @executor = executor
        @agent = agent
        @root = root
        @answer = answer
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [OpenLanes::Memory::Curation::Report]
      def call(subject)
        handle = Execution::Executor::Handle.new
        result = @executor.call(@agent, subject, root: @root, handle:)
        ordinal = subject.feature.ordinal.to_s
        # A dry run is ok and leaves no trace: nothing was said, so nothing is filed.
        said = result.ok && handle.trace ? @answer.call(handle.trace) : ""
        Report.new(ordinal:, ok: result.ok, note: result.note.to_s, outcomes: Memory.propose(said, plan: ordinal, root: @root))
      end
    end
  end
end
