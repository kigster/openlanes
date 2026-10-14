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

    # The coverage check `ok-to-merge` waits on (M15).
    #
    # @return [OpenLanes::Engine::CoverageGate]
    def coverage_gate(**) = CoverageGate.new(**)
  end
end
