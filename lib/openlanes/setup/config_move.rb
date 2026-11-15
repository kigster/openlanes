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
      # @raise [OpenLanes::Error] when the move cannot be made as asked
      def call(dry_run: false)
        from = File.join(@root, Project::LEGACY_FILE)
        return [] unless File.file?(from) || File.symlink?(from)

        to = File.join(@root, Project::FILE)
        refuse!(from, to)
        OpenLanes.move_directory(from, to) unless dry_run
        [[from, to]]
      end

      private

      # Every refusal, decided before anything moves and under a dry run too:
      # a preview that says "would move" for a move that will fail is wrong.
      #
      # @param from [String]
      # @param to [String]
      # @return [void]
      # @raise [OpenLanes::Error]
      def refuse!(from, to)
        raise Error, symlink(from) if File.symlink?(from)

        dir = File.dirname(to)
        raise Error, "#{dir} is a file, not a folder; move it aside so #{to} can be written" if File.exist?(dir) && !File.directory?(dir)
        raise Error, "#{to} is a directory; remove it so the config file can take its place" if File.directory?(to)
        raise Error, Project.both(to, from) if File.exist?(to)
      end

      # A relative link moved one folder down points at nothing, and a
      # project whose config file cannot be read runs on defaults, silently.
      #
      # @param from [String]
      # @return [String]
      def symlink(from)
        "#{from} is a symbolic link; replace it with the file it points to, " \
          "then run `#{Project::MOVE_COMMAND}` again"
      end
    end
  end
end
