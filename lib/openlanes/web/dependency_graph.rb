# frozen_string_literal: true

module OpenLanes
  module Web
    # Every plan and every `depends_on:` edge, for the Plan dependencies page
    # (plan 056). Read from the folders, archive included, rather than from
    # the board snapshot: the snapshot leaves the inactive subfolders out, and
    # the page shows them when Done is checked.
    #
    # The states travel with the plans, in {Plans::STATUSES} order, each
    # saying whether its plans live in an inactive subfolder, so the page's
    # filter keeps no copy of the vocabulary and no list of what is hidden by
    # default: both come from {Plans::Tree::INACTIVE_DIRS}, through the tree.
    class DependencyGraph
      # @param tree [OpenLanes::Plans::Tree] any tree over the `.plans`
      #   directory; its inactive subfolders are read whatever it was built with
      def initialize(tree)
        @tree = tree.everything
      end

      # @return [Hash{Symbol => Array<Hash>}] `states`, `plans` and `edges`
      def to_h = { states:, plans:, edges: }

      private

      # @return [Array<Hash>]
      def states
        Plans::STATUSES.map do |status|
          { key: status.key.to_s, emoji: status.emoji, name: status.label, archived: !Plans::Tree.subfolder_for(status).nil? }
        end
      end

      # @return [Array<Hash>]
      def plans
        @tree.subjects.map do |subject|
          feature = subject.feature
          { ordinal:  feature.ordinal.to_s,
            title:    feature.title,
            state:    subject.status.key.to_s,
            summary:  subject.summary,
            archived: @tree.inactive?(feature) }
        end
      end

      # One edge per declared dependency the tree holds a folder for: an
      # entry naming no plan has no box to point at.
      #
      # @return [Array<Hash>]
      def edges
        known = @tree.ordinals.to_set(&:to_s)
        known.flat_map do |to|
          Array(@tree.dependencies.depends_on(to)).select { known.include?(it) }.map { |from| { from:, to: } }
        end.sort_by { [it[:to], it[:from]] }
      end
    end
  end
end
