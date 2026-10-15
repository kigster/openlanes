# frozen_string_literal: true

module OpenLanes
  module Plans
    # A project's `.plans` directory: the folders in it, decoded and ordered.
    class Tree
      # @param dir [String] the `.plans` directory
      def initialize(dir:)
        @dir = File.expand_path(dir)
      end

      # @return [String] absolute path to the `.plans` directory
      attr_reader :dir

      # @return [Boolean]
      def exist? = File.directory?(dir)

      # @return [Array<OpenLanes::Plans::Feature>] ordered by number
      def features = @features ||= directories.filter_map { |p| Feature.parse(p) }.sort

      # @return [Array<OpenLanes::Plans::Subject>] ordered by number
      def subjects = @subjects ||= features.map { |f| Subject.new(f) }

      # @return [Array<OpenLanes::Plans::Ordinal>]
      def ordinals = features.map(&:ordinal)

      # Directories that carry no plan number. Reported, never processed.
      #
      # @return [Array<String>]
      def skipped = @skipped ||= directories.reject { |p| Feature.parse(p) }.map { |p| File.basename(p) }

      # Numbers claimed by more than one folder.
      #
      # A plan's number is its identity: branch names, pull request titles and
      # every `pull-requests.md` join on it. Two folders wearing the same number
      # make every one of those joins ambiguous, and nothing downstream can tell
      # which folder a `[002.00]` pull request belongs to.
      #
      # @return [Hash{OpenLanes::Plans::Ordinal => Array<String>}] number => dirnames
      def duplicates
        features.group_by(&:ordinal)
                .select { |_, group| group.size > 1 }
                .transform_values { |group| group.map(&:dirname) }
      end

      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [OpenLanes::Plans::Subject, nil]
      def find(ordinal)
        wanted = ordinal.is_a?(Ordinal) ? ordinal : Ordinal.parse(ordinal)
        subjects.find { |s| s.feature.ordinal == wanted }
      end

      # @return [Boolean] whether a plan with this number exists on disk
      def include?(ordinal) = !find(ordinal).nil?

      # @return [OpenLanes::Plans::Dependencies] who waits for whom, read from
      #   every `depends_on:` in this tree
      def dependencies = @dependencies ||= Dependencies.new(self)

      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [Array<String>] every plan that waits for this one; derived, never stored
      def blocks_of(ordinal) = dependencies.blocks_of(ordinal)

      # Forget everything read from disk, so a caller that has just renamed
      # folders sees the new state.
      #
      # @return [self]
      def reload
        @features = @subjects = @skipped = @dependencies = nil
        self
      end

      private

      # @return [Array<String>] absolute paths of every subdirectory
      def directories
        return [] unless exist?

        Dir.children(dir)
           .map { |c| File.join(dir, c) }
           .select { |p| File.directory?(p) }
           .reject { |p| File.basename(p).start_with?(".") }
           .sort
      end
    end
  end
end
