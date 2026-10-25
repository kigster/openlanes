# frozen_string_literal: true

module OpenLanes
  module Uml
    # The project as a graph: which definitions are drawn, the typed edges
    # between them, and how strongly each namespace depends on another.
    #
    # Classes are drawn; so is a module something includes, extends or
    # prepends, since that edge needs both ends. A module that only groups
    # constants is a namespace, not a node.
    class Model
      # @param definitions [Array<OpenLanes::Uml::Definition>]
      # @return [OpenLanes::Uml::Model]
      def self.build(definitions) = new(Index.new(definitions))

      # @return [OpenLanes::Uml::Namespaces]
      attr_reader :namespaces

      # @param index [OpenLanes::Uml::Index]
      def initialize(index)
        @index = index
        @namespaces = Namespaces.new(index.all)
        @mixins = index.all.flat_map(&:mixins).filter_map { index.resolve(it) }.to_set
      end

      # @return [Array<OpenLanes::Uml::Definition>] what the diagrams draw, by name
      def nodes = @index.all.select { node?(it.name) }

      # A module that only opens its own namespace (`module Shop` around
      # everything else) declares nothing there, and draws no empty box.
      #
      # @return [Array<String>] every namespace that declares anything, sorted
      def namespace_names = @index.all.reject { opener?(it) }.map { namespaces.of(it.name) }.uniq.sort

      # @return [Array<OpenLanes::Uml::Edge>] between drawn definitions, sorted
      def edges
        @index.all.flat_map { edges_from(it) }.select { node?(it.from) && node?(it.to) }
              .uniq { [it.from, it.to] }.sort_by { [it.from, it.to] }
      end

      # One count per pair of definitions, however often one names the other.
      #
      # @return [Hash{Array(String, String) => Integer}] [from, to] namespaces to a count
      def dependencies
        pairs = @index.all.flat_map { edges_from(it) }.uniq { [it.from, it.to] }
        pairs.map { [namespaces.of(it.from), namespaces.of(it.to)] }.reject { it.first == it.last }.tally
      end

      # @param name [String]
      # @return [Boolean]
      def node?(name)
        definition = @index[name]
        !definition.nil? && (definition.class? || @mixins.include?(name))
      end

      # @param name [String]
      # @return [Boolean]
      def mixin?(name) = @mixins.include?(name) && !@index[name].class?

      private

      # @param definition [OpenLanes::Uml::Definition]
      # @return [Boolean]
      def opener?(definition)
        definition.kind == :module && definition.references.empty? && definition.mixins.empty? &&
          namespaces.of(definition.name) == definition.name
      end

      # Typed edges first, so a parent that is also named in the body is
      # drawn once, as the parent.
      #
      # @param definition [OpenLanes::Uml::Definition]
      # @return [Array<OpenLanes::Uml::Edge>]
      def edges_from(definition)
        typed = [[:inherits, [definition.superclass].compact], [:includes, definition.mixins],
                 [:uses, definition.references]]
        typed.flat_map { |kind, refs| refs.filter_map { edge(definition.name, it, kind) } }
      end

      # @return [OpenLanes::Uml::Edge, nil]
      def edge(from, reference, kind)
        to = @index.resolve(reference)
        to && to != from ? Edge.new(from:, to:, kind:) : nil
      end
    end
  end
end
