# frozen_string_literal: true

# The `038` event bus over the process's Redis. Not memoized: the bus is a
# thin wrapper, and a memoized one would keep the first `redis` it saw, so a
# spec that stubs `redis` after another example resolved the bus would
# write into that example's store.
OpenLanes::Container.register_provider(:event_bus) do
  start do
    target.start(:redis)
    register("event_bus") { OpenLanes::Live::EventBus.for(target["redis"]) }
  end
end
