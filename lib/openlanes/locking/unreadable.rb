# frozen_string_literal: true

module OpenLanes
  module Locking
    # The register answered, but not with something that can be read.
    class Unreadable < OpenLanes::Error; end
  end
end
