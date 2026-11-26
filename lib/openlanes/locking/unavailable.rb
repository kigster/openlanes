# frozen_string_literal: true

module OpenLanes
  module Locking
    # There is no register on this machine at all: alock is not installed.
    # Permanent: callers stop asking for the rest of the run.
    class Unavailable < OpenLanes::Error; end
  end
end
