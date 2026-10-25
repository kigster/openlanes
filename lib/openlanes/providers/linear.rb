# frozen_string_literal: true

# Linear's GraphQL API, authenticated from the environment as the `linear`
# commands do. Built when first resolved, so a run without a key never
# touches it.
OpenLanes::Container.register_provider(:linear) do
  start do
    register("linear") { OpenLanes::Linear::API.new(token: OpenLanes::Linear::API.token_from_env) }
  end
end
