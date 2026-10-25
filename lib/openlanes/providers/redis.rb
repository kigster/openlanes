# frozen_string_literal: true

# The live run's Redis, at the address W16 resolves (`.openlanes.yml`, then
# `$REDIS_URL`, then the default), connected and answering PING. One per
# process, closed when the container shuts down.
OpenLanes::Container.register_provider(:redis) do
  start do
    register("redis", memoize: true) { OpenLanes::Live.connect(OpenLanes::Live.redis_url) }
  end

  stop { container["redis"].close if container.registered?("redis") }
end
