# frozen_string_literal: true

module OpenLanes
  module Live
    # The phases a new plan walks from each `starts:` value, for the idea
    # dialog's per-phase adapter and model rows (plan 040, D10).
    #
    # Derived, not listed: the states from where the lane enters the
    # {Plans::StateMachine::SPINE} onward, and the `phase:` of every agent
    # whose `handles:` names one of them and who serves that lane. A table
    # kept in the page would go stale the first time an agent moved.
    #
    #   Phases.wire(registry)
    #   # => { "building" => [{ phase: "build", toggle: nil }, { phase: "review", toggle: nil }, …], … }
    module Phases
      module_function

      # @param registry [OpenLanes::Agents::Registry]
      # @return [Hash{String => Array<Hash>}] `PhaseRow[]` in `types.ts`, by
      #   starts value; `toggle` is the spec.md key that switches the phase's
      #   agent off, so the dialog can hide a row its form has turned off
      def wire(registry) = Plans::Spec::STARTS.to_h { [it.to_s, walked(registry, it)] }

      # @param registry [OpenLanes::Agents::Registry]
      # @param starts [Symbol] one of {Plans::Spec::STARTS}
      # @return [Array<Hash>] in the order the plan reaches them
      def walked(registry, starts)
        agents = registry.all.select { it.phase && it.serves?(starts) }
        Plans::StateMachine.onward(entry(starts))
                           .flat_map { |state| agents.select { it.handles.include?(state) } }
                           .uniq(&:phase)
                           .map { { phase: it.phase, toggle: it.toggle } }
      end

      # Where a plan starting at +starts+ joins the spine: ⚪, or wherever
      # {Lifecycle::Lanes::HOPS} jumps it from there.
      #
      # @param starts [Symbol]
      # @return [Symbol] a status key
      def entry(starts) = Lifecycle::Lanes::HOPS.dig(starts, :new) || :new
    end
  end
end
