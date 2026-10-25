# frozen_string_literal: true

# The live run's Redis, at the address W16 resolves (`.openlanes.yml`, then
# `$REDIS_URL`, then the default), connected and answering PING. One per
# process, closed when the container shuts down.
#
# The connection is kept as it is made, and only that one is closed: the
# provider's own container has no `registered?`, and asking it for the key
# at shutdown would connect just to hang up.
OpenLanes::Container.register_provider(:redis) do
  start do
    register("redis", memoize: true) { @store = OpenLanes::Live.connect(OpenLanes::Live.redis_url) }
  end

  stop { @store&.close }
end
