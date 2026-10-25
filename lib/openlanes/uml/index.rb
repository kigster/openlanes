# frozen_string_literal: true

module OpenLanes
  module Uml
    # Every definition in the project by name, a class reopened across files
    # merged into one, and the lookup that turns a written constant into the
    # definition it names. Constants from outside the project (StandardError,
    # Dry::CLI::Command) resolve to nothing and draw no edge.
    class Index
      # @param definitions [Array<OpenLanes::Uml::Definition>]
      def initialize(definitions)
        @by_name = definitions.group_by(&:name).transform_values { merge(it) }
      end

      # @return [Array<OpenLanes::Uml::Definition>] sorted by name
      def all = @by_name.values.sort_by(&:name)

      # @param name [String]
      # @return [OpenLanes::Uml::Definition, nil]
      def [](name) = @by_name[name]

      # Ruby's lexical lookup, innermost scope first, then the top level.
      # `Plans::Status::STATUSES` names a constant no definition declares, so
      # the last segment is dropped until a prefix is one: the reference
      # uses `Plans::Status`.
      #
      # @param reference [OpenLanes::Uml::Reference]
      # @return [String, nil] the canonical name, a value type's owner for the type
      def resolve(reference)
        segments = reference.path.split("::")
        until segments.empty?
          found = lookup(segments.join("::"), reference.scope)
          return canonical(found) if found

          segments.pop
        end
        nil
      end

      # @param name [String]
      # @return [String] the owner of a folded value type, else +name+
      def canonical(name)
        definition = @by_name[name]
        definition&.owner ? canonical(definition.owner) : name
      end

      private

      # @return [String, nil]
      def lookup(path, scope)
        [*scope.map { "#{it}::#{path}" }, path].find { @by_name.key?(it) }
      end

      # @param parts [Array<OpenLanes::Uml::Definition>] one name's declarations
      # @return [OpenLanes::Uml::Definition]
      def merge(parts)
        kind = parts.map(&:kind).min_by { %i[class value module].index(it) }
        parts.first.with(kind:,
          superclass: parts.filter_map(&:superclass).first,
          mixins:     parts.flat_map(&:mixins),
          references: parts.flat_map(&:references),
          owner:      parts.filter_map(&:owner).first)
      end
    end
  end
end
