# frozen_string_literal: true

module OpenLanes
  module Uml
    # Every namespace as one box, and an arrow from each to every namespace it
    # depends on, labelled with how many of its definitions' edges cross. This
    # is the picture where coupling shows.
    class NamespaceMap
      # @param model [OpenLanes::Uml::Model]
      def initialize(model)
        @model = model
      end

      # @return [String] Mermaid
      def render
        boxes = @model.namespace_names.map { Mermaid.node(it, it) }
        arrows = @model.dependencies.sort.map { |(from, to), count| Mermaid.edge(from, to, Mermaid::ARROWS[:uses], count) }
        Mermaid.diagram(boxes + arrows)
      end
    end
  end
end
