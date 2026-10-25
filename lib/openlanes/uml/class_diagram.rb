# frozen_string_literal: true

module OpenLanes
  module Uml
    # One namespace's classes and the edges leaving them. A class from another
    # namespace that one of them inherits, includes or uses is drawn too,
    # under its full name, so the diagram says where the edge lands.
    class ClassDiagram
      # @param model [OpenLanes::Uml::Model]
      # @param namespace [String]
      def initialize(model, namespace)
        @model = model
        @namespace = namespace
      end

      # @return [String] Mermaid
      def render
        edges = @model.edges.select { inside?(it.from) }
        names = (members + edges.flat_map { [it.from, it.to] }).uniq.sort
        return Mermaid.diagram([%(  note "#{@namespace} declares no class")]) if names.empty?

        Mermaid.diagram(names.flat_map { box(it) } + edges.map { arrow(it) })
      end

      private

      # @return [Array<String>]
      def members = @model.nodes.map(&:name).select { inside?(it) }

      # @return [Boolean]
      def inside?(name) = @model.namespaces.of(name) == @namespace

      # @return [Array<String>] the class line, and a stereotype for a mixin
      def box(name)
        label = inside?(name) ? name.delete_prefix("#{@namespace}::") : name
        [Mermaid.node(name, label), (@model.mixin?(name) ? "  <<module>> #{Mermaid.id(name)}" : nil)].compact
      end

      # @return [String]
      def arrow(edge) = Mermaid.edge(edge.from, edge.to, Mermaid::ARROWS.fetch(edge.kind), edge.kind)
    end
  end
end
