# frozen_string_literal: true

module OpenLanes
  module Uml
    # One `class`, `module`, `X = Data.define(...)` or `X = Class.new(Y)` as
    # one file declares it. A class reopened in three files is three of these,
    # merged by {Index}.
    #
    # @!attribute name [String] the full constant name
    # @!attribute kind [Symbol] :class, :module or :value
    # @!attribute file [String] the path it was read from, relative to the root
    # @!attribute superclass [OpenLanes::Uml::Reference, nil]
    # @!attribute mixins [Array<OpenLanes::Uml::Reference>] include, extend, prepend
    # @!attribute references [Array<OpenLanes::Uml::Reference>] every other constant it names
    # @!attribute owner [String, nil] for a value type, the class it is declared in
    Definition = Data.define(:name, :kind, :file, :superclass, :mixins, :references, :owner) do
      # @param name [String]
      # @param kind [Symbol]
      # @param file [String]
      # @param superclass [OpenLanes::Uml::Reference, nil]
      # @param owner [String, nil]
      # @return [OpenLanes::Uml::Definition] with empty, appendable lists
      def self.open(name:, kind:, file:, superclass: nil, owner: nil)
        new(name:, kind:, file:, superclass:, mixins: [], references: [], owner:)
      end

      # @return [Boolean]
      def class? = kind == :class

      # @return [Array<String>] "OpenLanes::Plans::Tree" as its segments
      def segments = name.split("::")
    end
  end
end
