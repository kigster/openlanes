# frozen_string_literal: true

module OpenLanes
  # Class diagrams drawn from Ruby source read statically with Prism: the
  # project being built, or OpenLanes itself. Nothing is loaded or booted.
  module Uml
    # The gem's own checkout, which `openlanes uml self` draws.
    GEM_ROOT = File.expand_path("../..", __dir__)

    # What the gem's own diagrams are titled. Not the checkout's directory
    # name, which in a worktree is the branch's and would make every
    # worktree's diagrams differ from main's.
    SELF_TITLE = "OpenLanes"

    module_function

    # @param root [String]
    # @return [OpenLanes::Uml::Model]
    def model(root) = Model.build(Sources.new(root).definitions)

    # @param root [String]
    # @return [String] the namespace map, Mermaid
    def map(root) = NamespaceMap.new(model(root)).render

    # @param root [String]
    # @param namespace [String] as declared, e.g. "OpenLanes::Plans"
    # @return [String] that namespace's class diagram, Mermaid
    def class_diagram(root, namespace) = ClassDiagram.new(model(root), namespace).render

    # @param root [String]
    # @param title [String]
    # @return [OpenLanes::Uml::Writer]
    def writer(root, title:) = Writer.new(model(root), title:)
  end
end
