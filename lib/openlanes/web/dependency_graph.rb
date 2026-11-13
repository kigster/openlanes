# frozen_string_literal: true

module OpenLanes
  module Web
    # Every plan and every `depends_on:` edge, for the Plan dependencies page
    # (plan 056). Read from the folders, archive included, rather than from
    # the board snapshot: the snapshot leaves the inactive subfolders out, and
    # the page shows them when Done is checked.
    #
    # The states travel with the plans, in {Plans::STATUSES} order, so the
    # page's filter never keeps a copy of the vocabulary of its own.
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
      def states = Plans::STATUSES.map { { key: it.key.to_s, emoji: it.emoji, name: it.label } }

      # @return [Array<Hash>]
      def plans
        @tree.subjects.map do |subject|
          feature = subject.feature
          { ordinal:  feature.ordinal.to_s,
            title:    feature.title,
            state:    subject.status.key.to_s,
            summary:  Plans::Spec.summary(subject.read(Plans::Spec::FILENAME).to_s),
            archived: inactive?(feature) }
        end
      end

      # One edge per declared dependency the tree holds a folder for: an
      # entry naming no plan has no box to point at.
      #
      # @return [Array<Hash>]
      def edges
        known = @tree.ordinals.to_set(&:to_s)
        graph = Plans::Dependencies.new(@tree)
        known.flat_map do |to|
          Array(graph.depends_on(to)).select { known.include?(it) }.map { |from| { from:, to: } }
        end.sort_by { [it[:to], it[:from]] }
      end

      # @return [Boolean] whether the folder sits in an inactive subfolder
      def inactive?(feature) = Plans::Tree::SUBFOLDERS.include?(File.basename(File.dirname(feature.path)))
    end
  end
end
