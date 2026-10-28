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

    # The review label the reviewers' verdicts add up to (V4). A
    # `vulnerability` from anyone but the security reviewer counts as a plain
    # rejection, and is said in the log, so a reviewer straying outside its
    # remit is visible rather than silent.
    #
    # @param votes [Array<OpenLanes::Plans::Verdict::Vote>] one per reviewer
    # @return [OpenLanes::Plans::Verdict]
    def verdict(votes)
      Verdict.call(votes).tap do |verdict|
        verdict.ignored.each do |vote|
          UI.log("ignored vulnerability from #{vote.agent}: only #{Verdict::SECURITY_REVIEWER} may report one", level: :warn)
        end
      end
    end
  end
end
