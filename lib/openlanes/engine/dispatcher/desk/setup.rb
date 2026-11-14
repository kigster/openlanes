# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # What a {Desk} is built from, one value rather than seven keywords,
        # so the desk's constructor stays inside the parameter limit (A8).
        #
        # @!attribute runner [OpenLanes::Engine::Runner]
        # @!attribute state [OpenLanes::Engine::StateFile, nil] nil under a dry run
        # @!attribute rounds [Integer, nil] `--rounds`, a cap that only tightens
        # @!attribute stay [Boolean] whether the run idles past its fixed points
        # @!attribute journal [OpenLanes::Engine::EventJournal, nil]
        # @!attribute extensions [OpenLanes::Engine::Extensions, nil]
        # @!attribute budget [OpenLanes::Engine::Budget, nil] nil reads the cap
        #   and the spend from the runner's own event log
        Setup = Data.define(:runner, :state, :rounds, :stay, :journal, :extensions, :budget) do
          # @return [Setup] with every optional field defaulted to nil or false
          def initialize(runner:, state: nil, rounds: nil, stay: false, journal: nil, extensions: nil, budget: nil)
            super
          end
        end
      end
    end
  end
end
