# frozen_string_literal: true

module OpenLanes
  module Uml
    # Which namespace a constant belongs to: the unit the map draws, and the
    # unit one class diagram covers.
    #
    # - `A::B::C`, and deeper, belongs to `A::B`. In this gem that is
    #   `OpenLanes::Plans`, `OpenLanes::Engine`, `OpenLanes::CLI`.
    # - `A::B` belongs to `A`, unless `A::B` is itself such a namespace:
    #   `OpenLanes::UI` belongs to `OpenLanes`, `OpenLanes::Plans` to itself.
    # - A top-level constant that holds others is its own namespace. One that
    #   holds nothing is grouped by the directory Rails autoloads it from, so
    #   `User` in `app/models/user.rb` belongs to `app/models`; Zeitwerk gives
    #   those files no module to group them by.
    class Namespaces
      # The group for a top-level constant outside `app/`.
      TOP_LEVEL = "top level"

      # @param definitions [Array<OpenLanes::Uml::Definition>]
      def initialize(definitions)
        @files = definitions.to_h { [it.name, it.file] }
        @parents = definitions.flat_map { prefixes(it.segments) }.to_set
        @deep = definitions.map(&:segments).select { it.size >= 3 }.to_set { it.first(2).join("::") }
      end

      # @param name [String]
      # @return [String]
      def of(name)
        segments = name.split("::")
        return segments.first(2).join("::") if segments.size >= 3
        return name if @deep.include?(name) || (segments.size == 1 && @parents.include?(name))

        segments.size == 2 ? segments.first : autoload_group(name)
      end

      private

      # @return [Array<String>] every proper prefix of a name, as names
      def prefixes(segments) = (1...segments.size).map { segments.first(it).join("::") }

      # @return [String] "app/models" for a file under it, else {TOP_LEVEL}
      def autoload_group(name)
        dir = @files[name].to_s[%r{\Aapp/[^/]+(?=/)}]
        dir || TOP_LEVEL
      end
    end
  end
end
