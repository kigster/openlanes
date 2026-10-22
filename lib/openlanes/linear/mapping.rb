# frozen_string_literal: true

module OpenLanes
  module Linear
    # What a folder's state means to Linear.
    #
    # Linear gives every workflow state a *type* — one of five, fixed across
    # every workspace — and a *name*, which each team chooses for itself. A
    # team may call its started state "In Progress", "Doing" or "🚧 WIP", so
    # matching on the name alone works right up until it meets somebody else's
    # workspace. Each row here therefore carries both: the type, which is the
    # contract, and the name we would prefer if the team happens to have one.
    # {Push} resolves the name first and falls back to the type.
    #
    # Several states have no Linear equivalent at all — ⭕ Technical Block is
    # a reason, not a position in a workflow — so they map to the nearest
    # position and carry a label saying which reason.
    #
    # Two states are left out entirely; see {UNPLACED}.
    #
    # @!attribute [r] type
    #   @return [String] Linear's canonical type: backlog, unstarted, started,
    #     completed or canceled
    # @!attribute [r] name
    #   @return [String] the state name to prefer when the team has one
    # @!attribute [r] labels
    #   @return [Array<String>] labels that carry what the type cannot
    Placement = Data.define(:type, :name, :labels)

    # Linear's five workflow state types, in lifecycle order.
    TYPES = %w[backlog unstarted started completed canceled].freeze

    # Every plan state this tool is willing to place, keyed by
    # {OpenLanes::Plans::Status#key}.
    #
    # Between this and {UNPLACED} every entry in {OpenLanes::Plans::STATUSES} is
    # named exactly once, and a spec asserts it. That is the guard against the
    # failure this file is most prone to: a sixteenth state gets added,
    # nothing here changes, and its plans quietly import as Backlog with no
    # indication anything was missed.
    PLACEMENTS = {
      new:                Placement.new(type: "backlog", name: "Backlog", labels: []),
      researched:         Placement.new(type: "backlog", name: "Backlog", labels: %w[researched]),
      ready_for_planning: Placement.new(type: "backlog", name: "Backlog", labels: %w[spec-ready]),
      planned:            Placement.new(type: "unstarted", name: "Todo", labels: []),
      building:           Placement.new(type: "started", name: "In Progress", labels: []),
      # Both halves of building are one column on a board. A reader there
      # wants to know work is under way; which half is under way is this
      # tool's business, and the label carries it for anyone who does care.
      building_ui:        Placement.new(type: "started", name: "In Progress", labels: %w[frontend]),
      ready_for_review:   Placement.new(type: "started", name: "In Review", labels: []),
      in_review:          Placement.new(type: "started", name: "In Review", labels: []),
      verifying:          Placement.new(type: "started", name: "In Review", labels: []),
      completed:          Placement.new(type: "started", name: "In Review", labels: %w[ready-to-merge]),
      rejected:           Placement.new(type: "started", name: "In Review", labels: %w[changes-requested]),
      approved:           Placement.new(type: "completed", name: "Done", labels: []),
      deployed:           Placement.new(type: "completed", name: "Done", labels: %w[deployed]),
      blocked:            Placement.new(type: "unstarted", name: "Todo", labels: %w[blocked]),
      product_blocked:    Placement.new(type: "unstarted", name: "Todo", labels: %w[blocked-on-product]),
      bomb:               Placement.new(type: "unstarted", name: "Todo", labels: %w[blocked bomb]),
      deferred:           Placement.new(type: "backlog", name: "Backlog", labels: %w[deferred]),
      retroactive:        Placement.new(type: "completed", name: "Done", labels: %w[retroactive]),
      discarded:          Placement.new(type: "canceled", name: "Canceled", labels: [])
    }.freeze

    # States deliberately left out, and why.
    #
    # Both are real positions in this tool's lifecycle and neither is
    # obviously any position on a Linear board. Where they belong is a
    # statement about how a particular team works, and this tool does not know
    # that. Guessing would be worse than not knowing: an issue filed in the
    # wrong column reads exactly like an issue filed in the right one, and
    # nobody goes looking for a mistake that renders correctly.
    #
    # A plan in one of these states is reported and skipped. To import them,
    # decide where they belong and move the entry into {PLACEMENTS}.
    UNPLACED = {
      rewrite:     "the plan survives and its pull requests do not; whether that is work still to do " \
                   "or work abandoned depends on what the team does next",
      rolled_back: "it shipped and was pulled; whether that reopens this work or opens new work " \
                   "depends on what broke"
    }.freeze

    # Where one unit of work belongs, which is not always where its plan does.
    #
    # A plan in 🟡 Building has some units merged and some not started. Giving
    # every one of its issues the plan's own state says they are all in
    # progress, which is false about most of them and useless on a board. A
    # unit's pull requests are the better evidence, so they are used when
    # there are any.
    #
    # @param status [OpenLanes::Plans::Status] the plan's state
    # @param pulls [Array<OpenLanes::Plans::PullRequest>] the unit's
    # @return [OpenLanes::Linear::Placement, nil]
    def self.placement_for(status, pulls)
      return placement(status) if pulls.empty?
      return PLACEMENTS[:building].with(name: "In Review") if pulls.any?(&:open?)
      return PLACEMENTS[:approved] if pulls.all?(&:merged?)

      placement(status)
    end

    # Where a plan in this state belongs on a Linear board.
    #
    # @param status [OpenLanes::Plans::Status]
    # @return [OpenLanes::Linear::Placement, nil] nil when nobody has decided
    def self.placement(status) = PLACEMENTS[status.key]

    # Why a state is not imported, for the report that says so.
    #
    # @param status [OpenLanes::Plans::Status]
    # @return [String] the reason, or the louder one for a state nobody has considered at all
    def self.reason_unplaced(status)
      UNPLACED.fetch(status.key) do
        "no Linear placement has ever been decided for it — add one to Linear::PLACEMENTS"
      end
    end
  end
end
