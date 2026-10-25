# frozen_string_literal: true

module OpenLanes
  module Uml
    # The Ruby files a diagram is drawn from: `lib/`, and `app/` in a Rails
    # application. Never `spec/` or `test/`: the diagram is of what ships, and
    # a test double named like a class would draw an edge nothing has.
    class Sources
      # The file only a Rails application has.
      RAILS_MARKER = File.join("config", "application.rb")

      # @return [String]
      attr_reader :root

      # @param root [String] the project's root directory
      def initialize(root)
        @root = root
      end

      # @return [Array<String>] the directories read, relative to the root
      def directories = rails? ? %w[app lib] : %w[lib]

      # @return [Array<String>] absolute paths, sorted so output never depends on the filesystem's order
      def files = directories.flat_map { Dir.glob(File.join(root, it, "**", "*.rb")) }.sort

      # @return [Array<OpenLanes::Uml::Definition>] every file's, parsed
      def definitions = files.flat_map { Parser.parse(it, file: relative(it)) }

      private

      # @return [Boolean]
      def rails? = File.file?(File.join(root, RAILS_MARKER))

      # @return [String]
      def relative(path) = path.delete_prefix("#{root}/")
    end
  end
end
