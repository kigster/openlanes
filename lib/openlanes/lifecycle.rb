# frozen_string_literal: true

module OpenLanes
  # Operations that change which plans exist or what they are called:
  # minting a folder, drafting its brief, adopting an orphan pull request,
  # reconciling names with contents, draining answered questions, and
  # aging the ones nobody answers.
  module Lifecycle
    module_function

    # @param dir [String] the `.plans` directory
    # @param options [Hash] passed to {Creator#create}
    # @return [Dry::Monads::Result] Success(path) or Failure(message)
    def create(dir:, **) = Creator.new(dir:).create(**)

    # @param tree [OpenLanes::Plans::Tree]
    # @return [OpenLanes::Lifecycle::Resync::Dirs]
    def resync_dirs(tree:, **) = Resync::Dirs.new(tree:, **)

    # @return [OpenLanes::Lifecycle::Resync::Prs]
    def resync_prs(**) = Resync::Prs.new(**)

    # @return [OpenLanes::Lifecycle::Brief]
    def brief(**) = Brief.new(**)

    # @return [OpenLanes::Lifecycle::Unblocker]
    def unblocker(**) = Unblocker.new(**)

    # Bomb or defer the blocked plans past their limits (plan 009).
    #
    # @param tree [OpenLanes::Plans::Tree]
    # @param subjects [Array<OpenLanes::Plans::Subject>, nil] nil for every plan
    # @param since [Date, nil] `plans.aging_since`
    # @param now [Time]
    # @param commit [Boolean] false reports and changes nothing
    # @return [OpenLanes::Lifecycle::Aging::Result]
    def age(tree:, subjects: nil, since: nil, now: Time.now, commit: true)
      Aging.new(tree:, since:, now:).call(subjects:, commit:)
    end
  end
end
