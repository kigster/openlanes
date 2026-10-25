# frozen_string_literal: true

# The one place a child process starts (the `038` Process seam, named
# {OpenLanes::Spawner} so it cannot shadow `::Process`); a spec stubs it with
# {OpenLanes::Spawner::Fake}.
OpenLanes::Container.register_provider(:process) do
  start { register("process", OpenLanes::Spawner::System) }
end
