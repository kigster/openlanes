# frozen_string_literal: true

module OpenLanes
  module Plans
    # A project's `.plans` directory: the folders in it, decoded and ordered.
    #
    # Finished, deferred and discarded plans live one level down, in the
    # subfolders {INACTIVE_DIRS} names (decision N3), so the top level holds
    # only the plans somebody may still work on. A tree reads the top level
    # by default; `all: true` reads the subfolders too. Plan numbers span
    # both, since a number is never reused.
    class Tree
      # Where a plan in an inactive state lives, keyed by status key. The one
      # table `resync dirs` moves folders by and every reader skips by.
      INACTIVE_DIRS = {
        approved:  "archive",
        deployed:  "archive",
        deferred:  "deferred",
        discarded: "abandoned"
      }.freeze

      # The subfolders themselves, in the order `list-plans --all` shows them.
      SUBFOLDERS = INACTIVE_DIRS.values.uniq.freeze

      # @param status [OpenLanes::Plans::Status]
      # @return [String, nil] the subfolder a plan in this state belongs in, nil for the top level
      def self.subfolder_for(status) = INACTIVE_DIRS[status.key]

      # The plan folder a repository-relative path is inside, looking through
      # an inactive subfolder: `.plans/archive/003.00━━✅━━❯[…]━━x/spec.md`
      # names the plan `003.00━━✅━━❯[…]━━x`, not a plan called `archive`.
      #
      # @param path [String] e.g. a path from a pull request's diff
      # @return [String, nil] the folder's name, nil when the path is in no plan
      def self.plan_folder(path)
        parts = path.to_s.split("/")
        index = parts.index(OpenLanes::PLANS_DIR) or return nil
        parts = parts.drop(index + 1)
        parts = parts.drop(1) if SUBFOLDERS.include?(parts.first)
        parts.length >= 2 ? parts.first : nil # a file directly under .plans belongs to no plan
      end

      # @param dir [String] the `.plans` directory
      # @param all [Boolean] also read the inactive subfolders
      def initialize(dir:, all: false)
        @dir = File.expand_path(dir)
        @all = all
      end

      # @return [String] absolute path to the `.plans` directory
      attr_reader :dir

      # @return [Boolean] whether the inactive subfolders are read too
      def all? = @all

      # The same `.plans`, inactive subfolders included.
      #
      # @return [OpenLanes::Plans::Tree]
      def everything = all? ? self : (@everything ||= Tree.new(dir:, all: true))

      # @return [Boolean]
      def exist? = File.directory?(dir)

      # Open plans first, then each subfolder in {SUBFOLDERS} order; by
      # number within each group.
      #
      # @return [Array<OpenLanes::Plans::Feature>]
      def features
        @features ||= directories.filter_map { |p| Feature.parse(p) }.sort_by { |f| [group(f), f] }
      end

      # @return [Array<OpenLanes::Plans::Subject>] ordered by number
      def subjects = @subjects ||= features.map { |f| Subject.new(f) }

      # @return [Array<OpenLanes::Plans::Ordinal>]
      def ordinals = features.map(&:ordinal)

      # Every number in use, the inactive subfolders included: what a new
      # plan's number must stay clear of.
      #
      # @return [Array<OpenLanes::Plans::Ordinal>]
      def taken = everything.ordinals

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
      # An archived plan still holds its number, so the subfolders count.
      #
      # @return [Hash{OpenLanes::Plans::Ordinal => Array<String>}] number => dirnames
      def duplicates
        everything.features.group_by(&:ordinal)
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
        @everything&.reload
        self
      end

      private

      # @param feature [OpenLanes::Plans::Feature]
      # @return [Integer] 0 for the top level, else one past the subfolder's index
      def group(feature)
        parent = File.basename(File.dirname(feature.path))
        File.dirname(feature.path) == dir ? 0 : SUBFOLDERS.index(parent).to_i + 1
      end

      # @return [Array<String>] absolute paths of every plan-shaped subdirectory
      def directories
        return [] unless exist?

        top = children(dir).reject { |p| SUBFOLDERS.include?(File.basename(p)) }
        return top unless all?

        top + SUBFOLDERS.flat_map { |name| children(File.join(dir, name)) }
      end

      # @param parent [String]
      # @return [Array<String>]
      def children(parent)
        return [] unless File.directory?(parent)

        Dir.children(parent)
           .map { |c| File.join(parent, c) }
           .select { |p| File.directory?(p) }
           .reject { |p| File.basename(p).start_with?(".") }
           .sort
      end
    end
  end
end
