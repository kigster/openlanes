# frozen_string_literal: true

# The `038` event bus over the process's Redis.
OpenLanes::Container.register_provider(:event_bus) do
  start do
    target.start(:redis)
    register("event_bus", memoize: true) { OpenLanes::Live::EventBus.for(target["redis"]) }
  end
end
