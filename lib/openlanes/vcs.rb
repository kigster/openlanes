# frozen_string_literal: true

module OpenLanes
  # Git and GitHub: a checkout per plan, pushing a branch, and reading
  # pull requests. Everything that leaves the machine leaves through here.
  module Vcs
    module_function

    # @return [OpenLanes::Vcs::GitHub]
    def github = Container["github"]

    # @param root [String] repository root
    # @return [OpenLanes::Vcs::Worktree]
    def worktree(root:, warmup: Warmup.new, **) = Worktree.new(root:, warmup:, **)

    # @param root [String] the main checkout, whose installed dependencies
    #   a new worktree is given
    # @return [OpenLanes::Vcs::Prewarm]
    def prewarm(root:, **) = Prewarm.new(root:, **)

    # @param root [String] repository root
    # @return [OpenLanes::Vcs::Mainline]
    def mainline(root:, **) = Mainline.new(root:, **)

    # @param root [String] any checkout of the repository
    # @return [String] the branch `origin/HEAD` names, e.g. "main"
    def default_branch(root) = Refresh.default_branch(root)

    # @return [OpenLanes::Vcs::Publisher]
    def publisher(**) = Publisher.new(**)

    # @param github [OpenLanes::Vcs::GitHub]
    # @return [OpenLanes::Vcs::Review]
    def review(github: Container["github"]) = Review.new(github:)

    # @param root [String, nil] the checkout whose repository is synced; nil
    #   means the current directory's
    # @param github [OpenLanes::Vcs::GitHub]
    # @return [OpenLanes::Vcs::LabelSync]
    # Built by hand: the client is rooted at +root+, which no provider knows.
    def label_sync(root: nil, github: GitHub.new(chdir: root)) = LabelSync.new(github:)

    # Run before {label_sync}, once per repository: the repository's
    # {Plans::ReviewLabel::MIGRATED} label marks it done.
    #
    # @param root [String, nil] as for {label_sync}
    # @param github [OpenLanes::Vcs::GitHub]
    # @return [OpenLanes::Vcs::LabelMigration]
    # Built by hand: the client is rooted at +root+, which no provider knows.
    def label_migration(root: nil, github: GitHub.new(chdir: root)) = LabelMigration.new(github:)
  end
end
