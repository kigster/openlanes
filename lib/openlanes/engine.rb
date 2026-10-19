# frozen_string_literal: true

module OpenLanes
  # The run loop: which agent works which plan, in what order, until a round
  # changes nothing. It decides; {Execution} carries the decision out.
  module Engine
    module_function

    # @param options [Hash] passed to {RunWorkflow#initialize}
    # @return [OpenLanes::Engine::RunWorkflow] `openlanes run`, without the command
    def run(**) = RunWorkflow.new(**)

    # @param options [Hash] passed to {StartWorkflow#initialize}
    # @return [OpenLanes::Engine::StartWorkflow] `openlanes start`, without the command
    def start(**) = StartWorkflow.new(**)

    # @return [OpenLanes::Engine::Runner]
    def runner(**) = Runner.new(**)

    # @param tree [OpenLanes::Plans::Tree]
    # @return [OpenLanes::Engine::StateFile]
    def state_file(tree) = StateFile.new(path: StateFile.for(tree))

    # @return [OpenLanes::Engine::Tally]
    def tally(**) = Tally.new(**)

    # The coverage check `ready-to-merge` waits on (M15).
    #
    # @return [OpenLanes::Engine::CoverageGate]
    def coverage_gate(**) = CoverageGate.new(**)

    @agent_locks = ->(dir, own: []) { AgentLocks.new(root: dir, own:) }

    # The plans' alock register (W31), for the repository holding +dir+; nil
    # when the factory is, which is how the suite keeps `alock` unrun.
    #
    # @param dir [String] any directory in the repository, the plans' one
    # @param own [Array<String>] the engine's agents, whose locks are not outside ones
    # @return [OpenLanes::Engine::AgentLocks, nil]
    def agent_locks(dir, own: []) = @agent_locks&.call(dir, own:)

    # @param factory [#call, nil] answers `call(dir, own:)` with an {AgentLocks}
    # @return [void]
    def agent_locks=(factory)
      @agent_locks = factory
    end
  end
end
