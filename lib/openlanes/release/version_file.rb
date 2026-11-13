# frozen_string_literal: true

module OpenLanes
  module Release
    # The text of lib/openlanes/version.rb: the one place that knows how the
    # VERSION assignment is written, for reading it and for rewriting it.
    VersionFile = Data.define(:text)

    # Reopened rather than given a block: a constant inside the Data.define
    # block would land on Release, where Lockfile::PATH would clash with it.
    class VersionFile
      PATH = "lib/openlanes/version.rb"
      ASSIGNMENT = /^(\s*VERSION\s*=\s*)"([^"]*)"/

      # @return [String, nil] the assigned version, nil when there is none
      def version = text[ASSIGNMENT, 2]

      # @param version [String]
      # @return [String] the file's text with VERSION set to version
      def with(version) = text.sub(ASSIGNMENT) { "#{Regexp.last_match(1)}\"#{version}\"" }
    end
  end
end
