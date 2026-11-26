# frozen_string_literal: true

module OpenLanes
  module Locking
    # The register could not be read this time: alock failed, timed out, or
    # answered with something that is not a listing. Callers ask again.
    class Unreadable < OpenLanes::Error; end
  end
end
