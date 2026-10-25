# frozen_string_literal: true

# The real time source; a spec stubs it with {OpenLanes::Clock::Fake}.
OpenLanes::Container.register_provider(:clock) do
  start { register("clock", OpenLanes::Clock::System) }
end
