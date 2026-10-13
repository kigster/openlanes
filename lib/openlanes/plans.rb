# frozen_string_literal: true

module OpenLanes
  # The plan model: what a `.plans` folder is, which state it claims, and
  # which transitions it may take. Nothing in here spawns a process or talks
  # to a network; it reads and renames folders, and that is all.
  #
  # The module methods below are the front door. Callers outside this
  # namespace go through them rather than constructing the classes, so the
  # classes can be split or renamed without touching the CLI.
  module Plans
    module_function

    # @param dir [String] the `.plans` directory
    # @return [OpenLanes::Plans::Tree]
    def tree(dir = OpenLanes::PLANS_DIR) = Tree.new(dir:)

    # @param feature [OpenLanes::Plans::Feature]
    # @return [OpenLanes::Plans::Subject]
    def subject(feature) = Subject.new(feature)

    # @param path [String] a plan folder
    # @return [OpenLanes::Plans::Feature, nil]
    def feature(path) = Feature.parse(path)

    # @param text [String]
    # @return [OpenLanes::Plans::Ordinal, nil]
    def ordinal(text) = Ordinal.parse(text)

    # @param dir [String] a plan folder
    # @return [OpenLanes::Plans::Mailbox]
    def mailbox(dir) = Mailbox.new(dir:)

    # @param tree [OpenLanes::Plans::Tree]
    # @param project [String, nil]
    # @return [OpenLanes::Plans::Index]
    def index(tree:, project: nil) = Index.new(tree:, project:)
  end
end
