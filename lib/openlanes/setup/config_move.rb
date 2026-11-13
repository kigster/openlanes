# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Setup
    # Moves a project's legacy config file into {Project::DIR}, through
    # {OpenLanes.move_directory}, so a tracked file goes by `git mv` and its
    # history follows it. It never commits: the move is left staged for a
    # person to review.
    class ConfigMove
      # @param root [String] the project root
      def initialize(root:)
        @root = root
      end

      # @param dry_run [Boolean] report the move without making it
      # @return [Array<Array(String, String)>] each [from, to] moved, or that
      #   would be; empty when there is nothing to move
      # @raise [OpenLanes::Error] when the destination already exists
      def call(dry_run: false)
        from = File.join(@root, Project::LEGACY_FILE)
        return [] unless File.file?(from)

        to = File.join(@root, Project::FILE)
        raise Error, "both #{to} and #{from} exist; keep one and remove the other" if File.exist?(to)

        OpenLanes.move_directory(from, to) unless dry_run
        [[from, to]]
      end
    end
  end
end
