# frozen_string_literal: true

# This process's SemanticLogger, signed with the name {OpenLanes::Log.setup}
# gave it. Not memoized: setup may rename the process after the first resolve.
OpenLanes::Container.register_provider(:logger) do
  start { register("logger") { OpenLanes::Log.logger } }
end
