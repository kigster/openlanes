# frozen_string_literal: true

module OpenLanes
  # Git and GitHub: a checkout per plan, pushing a branch, and reading
  # pull requests. Everything that leaves the machine leaves through here.
  module Vcs
    module_function

    # @return [OpenLanes::Vcs::GitHub]
    def github = GitHub.new

    # @param root [String] repository root
    # @return [OpenLanes::Vcs::Worktree]
    def worktree(root:, **) = Worktree.new(root:, **)

    # @return [OpenLanes::Vcs::Publisher]
    def publisher(**) = Publisher.new(**)

    # @param github [OpenLanes::Vcs::GitHub]
    # @return [OpenLanes::Vcs::Review]
    def review(github: GitHub.new) = Review.new(github:)

    # @param root [String, nil] the checkout whose repository is synced; nil
    #   means the current directory's
    # @param github [OpenLanes::Vcs::GitHub]
    # @return [OpenLanes::Vcs::LabelSync]
    def label_sync(root: nil, github: GitHub.new(chdir: root)) = LabelSync.new(github:)
  end
end
