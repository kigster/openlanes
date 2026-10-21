# frozen_string_literal: true

module OpenLanes
  module Live
    # The port every publish, subscribe and stream append goes through.
    #
    # Engine, Live and Web used to call `store.publish`, `store.subscriber`
    # and `store.xadd` directly, on whichever of {Store} and {MemoryStore}
    # they were handed, so the two shared a duck type nobody declared. A bus
    # names that surface, and the stores become its backing: {RedisBus} over
    # {Store}, {MemoryBus} over {MemoryStore}. Key layout, stream ids and the
    # wire format are the store's, unchanged, because web cursors rely on them.
    module EventBus
      module_function

      # The bus over +store+, or +store+ itself when it already is one.
      #
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore, Base]
      # @return [Base]
      def for(store)
        case store
        when Base then store
        when MemoryStore then MemoryBus.new(store)
        else RedisBus.new(store)
        end
      end
    end
  end
end
