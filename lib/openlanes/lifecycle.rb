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

    # @param options [Hash] passed to {CreateWorkflow#initialize}
    # @return [OpenLanes::Lifecycle::CreateWorkflow] `openlanes create`, without the command
    def create_plan(**) = CreateWorkflow.new(**)

    # @param tree [OpenLanes::Plans::Tree]
    # @return [OpenLanes::Lifecycle::Resync::Dirs]
    def resync_dirs(tree:, **) = Resync::Dirs.new(tree:, **)

    # @return [OpenLanes::Lifecycle::Resync::Prs]
    def resync_prs(**) = Resync::Prs.new(**)

    # `resync prs` as one step: retitle (and adopt) on GitHub, or say why not.
    #
    # @param commit [Boolean] false previews and changes nothing
    # @param options [Hash] passed to {Resync::Prs#initialize}
    # @return [Dry::Monads::Result] Success(Array<Resync::Prs::Change>), or
    #   Failure({Refusal}) with status 69 when GitHub refused, or 73 when an
    #   orphan would be adopted in a linked worktree, where no plan is minted
    def retitle_prs(commit:, **)
      Dry::Monads::Result::Success.new(Resync::Prs.new(**).call(commit:))
    rescue Allocator::Refused => e
      Dry::Monads::Result::Failure.new(Refusal.new(message: e.message, status: 73))
    rescue OpenLanes::Error => e
      Dry::Monads::Result::Failure.new(Refusal.new(message: e.message, status: 69))
    end

    # @return [OpenLanes::Lifecycle::Brief]
    def brief(**) = Brief.new(**)

    # @param options [Hash] passed to {UnblockWorkflow#initialize}
    # @return [OpenLanes::Lifecycle::UnblockWorkflow] `openlanes unblock`, without the command
    def unblock(**) = UnblockWorkflow.new(**)

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
