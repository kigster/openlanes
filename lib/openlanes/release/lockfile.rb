# frozen_string_literal: true

module OpenLanes
  module Release
    # The text of Gemfile.lock, read for the versions it records of openlanes
    # itself. The one copy of that pattern: the bump and the specs that hold
    # the lock to version.rb all ask here.
    Lockfile = Data.define(:text)

    # Reopened rather than given a block, so PATH lands on Lockfile.
    class Lockfile
      PATH = "Gemfile.lock"
      # Matches both the PATH specs entry and the CHECKSUMS entry.
      ENTRY = /^\s+openlanes \(([^)]+)\)$/

      # @return [Array<String>] every entry's version, in order, repeats kept
      def entries = text.scan(ENTRY).flatten

      # @return [Array<String>] each distinct version the lock records
      def versions = entries.uniq
    end
  end
end
