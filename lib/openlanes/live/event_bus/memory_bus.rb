# frozen_string_literal: true

module OpenLanes
  module Live
    module EventBus
      # The bus for the suite and `--demo`, over {MemoryStore}: one process,
      # one keyspace, the same contract.
      class MemoryBus < Base
        # @param store [OpenLanes::Live::MemoryStore]
        def initialize(store = MemoryStore.new) = super
      end
    end
  end
end
