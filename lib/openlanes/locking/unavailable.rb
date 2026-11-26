# frozen_string_literal: true

module OpenLanes
  module Locking
    # The register cannot be reached at all: alock is not installed.
    class Unavailable < OpenLanes::Error; end
  end
end
