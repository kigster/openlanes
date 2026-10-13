# frozen_string_literal: true

module OpenLanes
  # The run loop: which agent works which plan, in what order, until a round
  # changes nothing. It decides; {Execution} carries the decision out.
  module Engine
    module_function

    # @return [OpenLanes::Engine::Runner]
    def runner(**) = Runner.new(**)

    # @param tree [OpenLanes::Plans::Tree]
    # @return [OpenLanes::Engine::StateFile]
    def state_file(tree) = StateFile.new(path: StateFile.for(tree))

    # @return [OpenLanes::Engine::Tally]
    def tally(**) = Tally.new(**)
  end
end
