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

    # The review label the reviewers' comments add up to (R3). A 💣 or 🔓
    # from anyone but the security reviewer is left out, and said in the log,
    # so a reviewer straying outside its remit is visible rather than silent.
    #
    # @param comments [Array<OpenLanes::Plans::Verdict::Comment, Hash>] each
    #   with `agent:` and `body:`
    # @param max_hmm [Integer] defaults to `review.max_hmm`, or
    #   `$OPENLANES_REVIEW_MAX_HMM` over it
    # @return [OpenLanes::Plans::Verdict]
    def verdict(comments, max_hmm: Config.current.max_hmm)
      Verdict.call(comments, max_hmm:).tap do |verdict|
        verdict.ignored.each do |comment|
          UI.log("ignored #{Verdict::MARKS[Verdict.mark_of(comment.body)]} from #{comment.agent || "an unnamed reviewer"}: " \
                 "only #{Verdict::SECURITY_REVIEWER} may use it",
            level: :warn)
        end
      end
    end
  end
end
