# frozen_string_literal: true

module OpenLanes
  module Plans
    # A plan-numbered folder that holds no plan: what is left behind when a
    # plan was moved somewhere else and the old folder would not die.
    #
    # Git applies a rename it merges in as a delete plus a create, and it
    # removes a directory only once it is empty. A `.DS_Store` (ignored, so
    # never deleted) kept `061.00━━⚪━━❯speed-up-openlanes` alive after the
    # plan was archived in another checkout. The tree read it as a ⚪ New plan,
    # a researcher was sent into a folder with no `spec.md`, and the engine's
    # own bookkeeping then filled it with a `state.json`, so the husk looked
    # more like a plan with every round.
    #
    # A folder is hollow when nothing in it but bookkeeping is left
    # ({BOOKKEEPING}, plus dotfiles). Hollow alone is not a husk: a folder
    # `openlanes create` has just made holds only its `state.json` until the
    # spec is written, and a second create running beside it must still see
    # that number as taken. A hollow folder is a husk when a folder in an
    # inactive subfolder that is not hollow carries its number: the merge case
    # exactly, since the plan lives on under `archive/` (or `discarded/`, …)
    # and a number is never reused. A hollow folder with no such twin is left
    # to the dispatcher, which starts no agent on a state whose required
    # files are missing.
    #
    # @!attribute [r] path
    #   @return [String] the husk, absolute
    # @!attribute [r] twin
    #   @return [String] the folder that holds the plan now, relative to
    #     `.plans` (e.g. `archive/061.00━━✅━━❯[2026-11-13]━━speed-up-openlanes`)
    class Husk < Data.define(:path, :twin)
      # Files the engine writes about a plan, never the plan itself.
      BOOKKEEPING = [PlanState::FILENAME, "blocked.md"].freeze

      # @param path [String] a folder under `.plans`
      # @return [Boolean]
      def self.husk?(path)
        File.directory?(path) && Feature.parse(path) && hollow?(path) && !twin_of(path).nil?
      end

      # @param path [String]
      # @return [OpenLanes::Plans::Husk, nil] the husk, nil when the folder is not one
      def self.at(path) = (new(path: File.expand_path(path), twin: twin_of(path)) if husk?(path))

      # @param path [String]
      # @return [Boolean] whether nothing but bookkeeping and dotfiles is left
      def self.hollow?(path) = leftovers(path).all? { BOOKKEEPING.include?(it) }

      # Another folder with the same number that still holds a plan, in one
      # of the inactive subfolders. Only there: a hollow archived folder
      # beside a live plan of the same number is a duplicate to report, not
      # a husk to hide.
      #
      # @param path [String]
      # @return [String, nil] relative to `.plans`
      def self.twin_of(path)
        mine = Feature.parse(path) or return nil
        root = plans_root(path)
        siblings(root).find do |other|
          other != File.expand_path(path) && Feature.parse(other)&.ordinal == mine.ordinal && !hollow?(other)
        end&.delete_prefix("#{root}/")
      end

      # @param path [String]
      # @return [Array<String>] entries that are not dotfiles
      def self.leftovers(path) = Dir.children(path).reject { it.start_with?(".") }

      # @param path [String] a plan folder
      # @return [String] the `.plans` directory it sits in, through a subfolder
      def self.plans_root(path)
        parent = File.dirname(File.expand_path(path))
        Tree::SUBFOLDERS.include?(File.basename(parent)) ? File.dirname(parent) : parent
      end

      # @param root [String]
      # @return [Array<String>] every directory an inactive plan could be in
      def self.siblings(root)
        Tree::SUBFOLDERS.map { File.join(root, it) }.select { File.directory?(it) }.flat_map do |dir|
          Dir.children(dir).map { File.join(dir, it) }.select { File.directory?(it) }
        end
      end
      private_class_method :leftovers, :plans_root, :siblings

      # @return [String] the folder's name
      def dirname = File.basename(path)

      # @return [String] one line for a report
      def to_s
        "#{dirname}: an empty husk, not a plan (the plan lives on as #{twin}); safe to remove"
      end
    end
  end
end
