# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module OpenLanes
  module Supervision
    # A copy of the built page kept aside while {WebRebuild} builds a new
    # one (plan 069.00, D3). `vite build` empties its out dir before it
    # writes, so a build that fails would otherwise leave no page at all.
    class PageBackup
      # @param dist [String] the built page's directory, `web/dist`
      def initialize(dist)
        @dist = dist
      end

      # Copies the page into a directory only this user can read. Nothing
      # to keep when there is no page yet.
      #
      # @return [self]
      # @raise [SystemCallError] when the page cannot be read; the half
      #   copy is removed first
      def keep
        return self unless File.directory?(@dist)

        @kept = Dir.mktmpdir("openlanes-web-dist")
        FileUtils.cp_r(File.join(@dist, "."), @kept)
        self
      rescue SystemCallError
        discard
        raise
      end

      # Puts the kept page back in place of whatever the build left.
      #
      # @return [void]
      # @raise [SystemCallError] when the page's directory cannot be written
      def restore
        return unless @kept

        FileUtils.rm_rf(@dist)
        FileUtils.mkdir_p(@dist)
        FileUtils.cp_r(File.join(@kept, "."), @dist)
        discard
      end

      # @return [void]
      def discard
        FileUtils.rm_rf(@kept) if @kept
        @kept = nil
      end
    end
  end
end
