# frozen_string_literal: true

module OpenLanes
  module Web
    # One store per Puma thread. {Live::Store} holds a single Redis
    # connection, which two threads must not share: an event stream polling
    # on one thread and a command posted on another would interleave their
    # replies on the wire.
    #
    # Puma's threads are pooled, so the map is bounded by the pool's size.
    class Stores
      # Every thread gets the same store: {Live::MemoryStore}, which lives in
      # this process and is already synchronised.
      #
      # @param store [OpenLanes::Live::MemoryStore]
      # @return [OpenLanes::Web::Stores]
      def self.shared(store) = new { store }

      # @yieldreturn [OpenLanes::Live::Store] a new store
      def initialize(&factory)
        @factory = factory
        @mutex = Mutex.new
        @by_thread = {}
      end

      # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      def current = @mutex.synchronize { @by_thread[Thread.current] ||= @factory.call }

      # Drop and close this thread's store. A thread that is not one of
      # Puma's pooled ones calls it when done, or the map would keep a
      # connection for every such thread that ever ran. A shared store is
      # dropped but not closed: the others still hold it.
      #
      # @return [void]
      def release
        store = @mutex.synchronize { @by_thread.delete(Thread.current) }
        store&.close unless @mutex.synchronize { @by_thread.value?(store) }
      end

      # @return [void]
      def close
        stores = @mutex.synchronize { @by_thread.values.uniq.tap { @by_thread.clear } }
        stores.each(&:close)
      end
    end
  end
end
