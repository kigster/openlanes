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
      # @raise [StandardError] when the page cannot be read; the half
      #   copy is removed first
      def keep
        return self unless File.directory?(@dist)

        @kept = Dir.mktmpdir("openlanes-web-dist")
        FileUtils.cp_r(File.join(@dist, "."), @kept)
        self
      rescue StandardError
        discard
        raise
      end

      # Puts the kept page back in place of whatever the build left, and
      # lets go of the copy whether or not that worked: a copy kept after
      # a failed restore was one more directory left in tmp per restart.
      #
      # A page the build never touched is left alone. Rewriting it was how
      # an installed gem's read-only `web/` came to be reported as a page
      # that "could not be put back" while it sat there whole.
      #
      # The copy is laid out beside the page and renamed into place, so a
      # restore that fails half way leaves what the build left, not a
      # page with some of its files.
      #
      # @return [void]
      # @raise [SystemCallError] when the page's directory cannot be written
      def restore
        swap_in if @kept && !intact?
      ensure
        discard
      end

      # @return [void]
      def discard
        FileUtils.rm_rf(@kept) if @kept
        @kept = nil
      end

      private

      # @return [void]
      def swap_in
        staged = "#{@dist}.restoring"
        FileUtils.rm_rf(staged)
        FileUtils.mkdir_p(staged)
        FileUtils.cp_r(File.join(@kept, "."), staged)
        FileUtils.rm_rf(@dist)
        File.rename(staged, @dist)
      ensure
        FileUtils.rm_rf(staged)
      end

      # @return [Boolean] whether the page is, file for file, the one kept
      def intact?
        names = entries(@kept)
        names == entries(@dist) && names.all? { same?(File.join(@kept, it), File.join(@dist, it)) }
      rescue SystemCallError
        false
      end

      # @param dir [String]
      # @return [Array<String>] every path under it, relative and sorted
      def entries(dir) = Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).sort

      # @param kept [String]
      # @param built [String]
      # @return [Boolean]
      def same?(kept, built)
        return File.directory?(built) if File.directory?(kept)

        File.file?(built) && FileUtils.compare_file(kept, built)
      end
    end
  end
end
