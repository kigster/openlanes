# frozen_string_literal: true

module OpenLanes
  module Uml
    # The Mermaid vocabulary both diagrams share. Constant names carry `::`,
    # which Mermaid does not accept in an identifier, so every node gets an
    # id and keeps its real name as a label.
    module Mermaid
      # From the edge's source to its target, as the arrow points.
      ARROWS = { inherits: "--|>", includes: "..|>", uses: "..>" }.freeze

      module_function

      # @param name [String] a constant or namespace name
      # @return [String] a Mermaid identifier
      def id(name) = name.gsub(/[^A-Za-z0-9_]/, "_")

      # @param name [String]
      # @param label [String]
      # @return [String] one `class` line
      def node(name, label) = %(  class #{id(name)}["#{label}"])

      # @param from [String]
      # @param to [String]
      # @param arrow [String]
      # @param label [String]
      # @return [String] one edge line
      def edge(from, to, arrow, label) = "  #{id(from)} #{arrow} #{id(to)} : #{label}"

      # @param lines [Array<String>]
      # @return [String] a whole diagram, newline-terminated
      def diagram(lines) = ["classDiagram", *lines].join("\n").concat("\n")
    end
  end
end
