# frozen_string_literal: true

module OpenLanes
  module Locking
    # The register could not be read this time: Redis did not answer, or
    # agent-lock failed underneath. Callers ask again.
    class Unreadable < OpenLanes::Error; end
  end
end
