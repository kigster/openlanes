# frozen_string_literal: true

require "aasm"

module OpenLanes
  module Plans
    # The state machine for one plan folder.
    #
    # The whole topology is the `aasm` block below, and it is nowhere else. To
    # change what may follow what, edit an event's `from:` list. To add a state,
    # add it to {STATUSES} and give it an event. There is no second table to keep
    # in step: {inbound}, {outbound}, {edge?} and `terminal?` are all read back
    # off these declarations.
    #
    # Two rules hold the rest together:
    #
    # 1. **The guard for entering a state is that state's own invariant.** There
    #    is one guard method, {#justified?}, and it reads the destination off the
    #    transition in flight — so a destination is named once, in `to:`.
    # 2. **The state lives in the folder name.** There is no column and no
    #    database. A successful transition renames the directory, which is why
    #    firing an event is a real side effect and asking a question is not.
    class StateMachine
      include AASM

      # Raised when a transition is refused, carrying the reason rather than
      # AASM's "failed callback #17".
      class Refused < Error; end

      # The forward path a bare {#promote!} walks. Everything off this spine —
      # blocking, deferring, discarding — has to be named explicitly, which is
      # the entire reason for having a machine rather than a rename.
      #
      # 🔴 rejoins at 🎨 rather than continuing: fixing review comments puts the
      # work back through both halves of building, it does not skip the reviewer
      # and it does not assume the half nobody complained about still holds.
      SPINE = {
        retroactive:        :planned,
        new:                :researched,
        researched:         :ready_for_planning,
        ready_for_planning: :planned,
        planned:            :building,
        building:           :building_ui,
        building_ui:        :ready_for_review,
        ready_for_review:   :in_review,
        in_review:          :verifying,
        verifying:          :completed,
        completed:          :approved,
        approved:           :deployed,
        rejected:           :building_ui,
        rolled_back:        :ready_for_review,
        rewrite:            :planned
      }.freeze

      # One step back along the spine, for the one move that goes backwards: a
      # person discarding an interrupted round (W9) sends the plan back to the
      # state the work started from. Derived from {SPINE}, walking it from ⚪:
      # each state on that path steps back to the one before it, as far as 🏁,
      # the last state an agent works in. States off the path (🔴 🚫 ⏪ and
      # the birth state) have no single state behind them and step back
      # nowhere.
      #
      RETREAT = Enumerator.produce(:new) { SPINE.fetch(it) { raise StopIteration } }
                          .take_while { it != :approved }
                          .each_cons(2).to_h { |before, after| [after, before] }
                          .freeze

      # Preference order when several states fit a folder's contents at once.
      # Read top to bottom: the loudest fact wins. A discard outranks everything,
      # a block outranks progress, and `retroactive` is last because it is the
      # absence of documents rather than the presence of any.
      PREFERENCE = %i[
        discarded rolled_back rewrite deferred blocked product_blocked bomb
        deployed approved rejected completed verifying in_review ready_for_review building_ui building planned ready_for_planning
        researched new
        retroactive
      ].freeze

      # States whose members a folder's *contents* cannot tell apart. Within a
      # family the current name always wins, because re-deriving it would be a
      # guess dressed up as a correction.
      #
      # ⭕ and 🛑 both mean "a human must decide before this moves"; *which*
      # human is recorded nowhere but the emoji.
      #
      # ⭐ 🟡 🎨 look identical on disk: a `spec.md` and a `plan.md` with work
      # units in it. Whether nobody has started, the back end is under way, or
      # the interface is, is recorded only by the agent that renamed the folder
      # when it started. 🟢 👀 🔴 add an open pull request and are just as
      # mute about whether a reviewer has seen it. So `resync` never moves
      # between any of them; they advance by events alone.
      #
      # Order matters: the members run weakest claim first, and a folder
      # arriving from outside lands on the weakest member its contents fit.
      # Contents that fit the family justify only its floor, never its ceiling.
      FAMILIES = [
        %i[blocked product_blocked bomb],
        %i[planned building building_ui ready_for_review in_review verifying completed rejected]
      ].freeze

      # States the agent loop leaves alone: work that is finished (✅ 😎), work
      # that was dropped (❌), and work waiting on a human (⭕ 🛑 💣 💤).
      # Everything else is fair game for a specialist.
      #
      # ✅ Approved is here deliberately. A plan reaching it, from 🧪 once its
      # pull request merged, is the end of the loop, not a step in it: no agent
      # handles `approved`. Merging is the one act in this lifecycle that changes
      # a branch everyone else builds on, and an autonomous loop that does it
      # unattended has no way to be wrong quietly.
      #
      # Moving `approved` out of this list is therefore a decision about blast
      # radius rather than about topology. If it ever moves, something has to own
      # `approved -> deployed`, and today nothing does.
      SETTLED = %i[approved deployed discarded blocked product_blocked bomb deferred].freeze

      # Every state an agent that may sign `Blocked` works in. A block the
      # machine refuses is reported as a failed attempt and parks nothing, so a
      # state missing here turns an honest "I need a decision" into a failure.
      # The agents spec checks every prompt that describes blocking against it.
      #
      # Review is absent: a reviewer rules, it does not ask.
      BLOCKABLE = %i[new researched retroactive ready_for_planning planned building building_ui rejected].freeze

      # Rerouting a transition below makes the hand-drawn
      # `docs/img/plan-spec-build.png` stale — `just docs` will show you, because
      # the mermaid source in the generated document is derived from this block.
      aasm do
        # The vocabulary is defined once, in {STATUSES}. This machine may not
        # quietly know a different set.
        OpenLanes::Plans::STATUSES.each { |status| state status.key }

        event :specify, guard: :justified? do
          transitions from: %i[retroactive blocked product_blocked bomb deferred], to: :new
        end

        event :research, guard: :justified? do
          transitions from: %i[new retroactive blocked product_blocked bomb deferred], to: :researched
        end

        # The specification is done and the planner has not started. Entered
        # by the harness when `yoda-writer` completes; `resync` reaches it on a
        # blank `plan.md`. Without it ⭐ Planned required a file only the agent
        # handling ⭐ Planned writes, and nothing could enter it. The planner
        # answers `depends_on:` here, while it plans (A17).
        event :ready_to_plan, guard: :justified? do
          transitions from: %i[researched new retroactive rewrite blocked product_blocked bomb deferred],
            to: :ready_for_planning
        end

        # `new` stays in this list. The spine routes a plan through research, and
        # that is what the agent loop follows — but a specification somebody has
        # already researched by hand should not have to pretend otherwise to get
        # planned. What research buys is not enforced here; it is enforced by
        # `yoda-writer` handling `researched` and nothing else.
        event :plan, guard: :justified? do
          transitions from: %i[ready_for_planning researched new retroactive rewrite blocked product_blocked bomb deferred],
            to: :planned
        end

        # From 👀 too (plan 035): under `desired_codebase_quality: standard`
        # a `review-ok-not-perfect` pull request goes back to the builders
        # at 🟡, a lighter send-back than `high`'s 🔴.
        event :build, guard: :justified? do
          transitions from: %i[planned rewrite approved rolled_back retroactive blocked product_blocked bomb deferred
                               in_review],
            to: :building
        end

        # Building hands off rather than finishing. A plan with no interface work
        # still passes through Building UI: `rey-frontend` says there is nothing
        # to build and moves it on, which costs one cheap round and keeps the
        # spine one shape instead of two. `rejected` re-enters here rather than
        # going straight back to review, because a change request reopens the
        # implementation and neither half can assume the other still holds.
        event :build_ui, guard: :justified? do
          transitions from: %i[building rejected], to: :building_ui
        end

        # The pair lands one pull request, and whichever half finishes last
        # carries the plan to review from wherever the folder stands.
        event :submit, guard: :justified? do
          transitions from: %i[building building_ui rejected rolled_back], to: :ready_for_review
        end

        event :review, guard: :justified? do
          transitions from: %i[ready_for_review], to: :in_review
        end

        # hansolo's approval no longer ends the loop (plan 014, M1): the app is
        # run through the pull request's `## How to test` first, by
        # chewie-verifier, before anything may merge.
        event :verify, guard: :justified? do
          transitions from: %i[in_review], to: :verifying
        end

        # Every pull request is `ready-to-merge` (P1): palpatine weighs each
        # one, and the engine merges them one at a time.
        event :complete, guard: :justified? do
          transitions from: %i[verifying], to: :completed
        end

        # `in_review` stays a source: a person who merges on GitHub while
        # hansolo is still reading has approved it all the same (M4). So do
        # 🧪 and 🏁, for a merge before the engine or palpatine has ruled,
        # and for the `merge-manually` pull request a person merges (P3).
        event :approve, guard: :justified? do
          transitions from: %i[in_review verifying completed retroactive], to: :approved
        end

        # From 🧪 as well as 👀: a verification that fails sends the plan back
        # to the builders exactly as a review that fails does. From 🏁 too:
        # a pull request that no longer rebases cleanly onto `main` after
        # its sibling merged goes back to luke and rey (P5), and a person may
        # still reject one on GitHub while it waits for them.
        event :request_changes, guard: :justified? do
          transitions from: %i[in_review verifying completed], to: :rejected
        end

        event :slop, guard: :justified? do
          transitions from: %i[in_review], to: :rewrite
        end

        event :deploy, guard: :justified? do
          transitions from: %i[approved], to: :deployed
        end

        # 🚀 is not the end of the line. A release that breaks in production comes
        # back through ⏪, which needs its own proof on disk: by the time work is
        # deployed every pull request is merged, so 🟢's "at least one open pull
        # request" guard would refuse a direct return, permanently.
        event :rollback, guard: :justified? do
          transitions from: %i[deployed], to: :rolled_back
        end

        # 💣 leaves back through the block it came from: once an answer is in,
        # `blocked.md` says whether the question was technical or product, and
        # the ordinary unblock path takes it from there.
        event :block, guard: :justified? do
          transitions from: BLOCKABLE + %i[bomb], to: :blocked
        end

        event :block_on_product, guard: :justified? do
          transitions from: BLOCKABLE + %i[bomb], to: :product_blocked
        end

        # Fired by the aging sweep alone, never by `resync`: a plan others
        # depend on has sat blocked past the limit, and the run halts on it.
        event :bomb, guard: :justified? do
          transitions from: %i[blocked product_blocked], to: :bomb
        end

        event :defer, guard: :justified? do
          transitions from: BLOCKABLE + %i[blocked product_blocked], to: :deferred
        end

        # Anything, from anywhere, may be dropped for good.
        event :discard, guard: :justified? do
          transitions from: OpenLanes::Plans::STATUSES.map(&:key) - %i[discarded], to: :discarded
        end

        # Back one step, fired only by {#retreat!}. It is the one event with
        # several destinations, and it is left out of {inbound}, {outbound}
        # and {event_for}: those describe how work moves on, which is what
        # the documentation, the diagram and {#may?} are about, and a person
        # sending work back is not a way for it to move on.
        event :step_back, guard: :justified? do
          RETREAT.each { |from, to| transitions from:, to: }
        end

        # A transition is not a bookkeeping entry: it is the folder moving.
        after_all_transitions :rename!
      end

      class << self
        # Destination => the event that reaches it. Every event above has exactly
        # one `to:`, which is what lets `--to <state>` name a destination rather
        # than making callers learn the verbs.
        #
        # @return [Hash{Symbol => Symbol}]
        def event_for
          @event_for ||= forward_events.each_with_object({}) { |event, map|
            event.transitions.each { |t| map[t.to] ||= event.name }
          }.freeze
        end

        # Destination => the states that may legitimately reach it.
        #
        # `retroactive` is absent: it is a birth state, produced by
        # `create --after` for work that shipped undocumented.
        #
        # @return [Hash{Symbol => Array<Symbol>}]
        def inbound
          @inbound ||= forward_events.each_with_object({}) { |event, map|
            event.transitions.each { |t| (map[t.to] ||= []).concat(Array(t.from)) }
          }.transform_values { |froms| froms.uniq.freeze }.freeze
        end

        # Source => the states it may reach.
        #
        # @return [Hash{Symbol => Array<Symbol>}]
        def outbound_map
          @outbound_map ||= inbound.each_with_object({}) { |(to, froms), map|
            froms.each { |from| (map[from] ||= []) << to }
          }.transform_values(&:freeze).freeze
        end

        # @param key [Symbol]
        # @return [Array<Symbol>]
        def outbound(key) = outbound_map.fetch(key, [])

        # @param from [Symbol]
        # @param to [Symbol]
        # @return [Boolean] whether the topology permits this edge at all
        def edge?(from, to) = outbound(from).include?(to)

        # Every event but {RETREAT}'s.
        #
        # @return [Array<AASM::Core::Event>]
        def forward_events = aasm.events.reject { it.name == :step_back }

        # @param key [Symbol]
        # @return [Array<Symbol>] the family +key+ belongs to, empty when it has none
        def family_of(key) = FAMILIES.find { |family| family.include?(key) } || []
      end

      # @param subject [#status, #file?, #read, #pull_requests, #rename_to]
      def initialize(subject)
        @subject = subject
        @key = subject.status.key
      end

      # @return [Object] the plan folder this machine speaks for
      attr_reader :subject

      # @return [Symbol] the state right now
      attr_reader :key

      # @return [OpenLanes::Plans::Status]
      def status = STATUS_BY_KEY.fetch(key)

      # AASM keeps state in an ORM column; we keep it in a directory name. These
      # three methods are the whole of that adaptation.
      #
      # @return [Symbol]
      def aasm_read_state(_name = :default) = @key

      # @return [Boolean]
      def aasm_write_state(new_state, name = :default) = aasm_write_state_without_persistence(new_state, name)

      # @return [Boolean]
      def aasm_write_state_without_persistence(new_state, _name = :default)
        @key = new_state
        true
      end

      # States reachable right now, guards applied. A step back is not among
      # them: only {#retreat!} takes it.
      #
      # @return [Array<Symbol>]
      def allowed = aasm.states(permitted: true).map(&:name) & self.class.outbound(key)

      # @param to [Symbol]
      # @return [Boolean] whether that move is permitted right now
      def may?(to) = allowed.include?(to)

      # Where a move toward `to` honestly lands. A family's members differ
      # only in what their invariants read, so when `to` refuses and the next
      # spine state is its sibling and fits, that sibling is the landing.
      #
      # @param to [Symbol]
      # @return [Symbol] `to`, or its sibling on the spine
      def onward(to)
        return to if may?(to)

        sibling = SPINE[to]
        sibling && self.class.family_of(to).include?(sibling) && may?(sibling) ? sibling : to
      end

      # The next state along the spine, whether or not its guard passes.
      #
      # @return [Symbol, nil]
      def spine_next = SPINE[key]

      # Move the folder. With no argument it walks one step along the {SPINE}.
      #
      # A refusal is information — it means the phase has not actually happened
      # yet — so it arrives as {Refused} carrying the reason, never as `false`.
      #
      # @param to [Symbol] destination, defaulting to the next spine state
      # @return [OpenLanes::Plans::Status] the state now occupied
      # @raise [OpenLanes::Plans::StateMachine::Refused]
      def promote!(to = spine_next)
        raise Refused, "#{describe(key)} is terminal — nothing follows it" if to.nil?
        raise Refused, "nothing can reach #{describe(to)}" unless self.class.event_for.key?(to)
        raise Refused, refusal(to) unless may?(to)

        aasm.fire!(self.class.event_for.fetch(to))
        status
      end

      # @return [Symbol, nil] the state one step back, nil when there is none
      def previous = RETREAT[key]

      # Move the folder one step back along the spine (W9).
      #
      # @return [OpenLanes::Plans::Status] the state now occupied
      # @raise [OpenLanes::Plans::StateMachine::Refused] when nothing is
      #   behind this state, or the folder's contents do not justify it
      def retreat!
        refusal = retreat_refusal and raise Refused, refusal

        aasm.fire!(:step_back)
        status
      end

      # @return [String, nil] why {#retreat!} would be refused, nil when it would not
      def retreat_refusal
        to = previous or return "#{describe(key)} has no state behind it to go back to"
        return nil if aasm.may_fire_event?(:step_back)

        STATUS_BY_KEY.fetch(to).violation(subject) || "#{describe(key)} cannot go back to #{describe(to)}"
      end

      # The state a folder's contents justify — the answer to "well, what should
      # it be, then?". This is what `resync dirs` renames toward.
      #
      # Invariants are *minimum* requirements, not exact matches: a ⚪ folder
      # that has since grown a `plan.md` still satisfies ⚪, and is nonetheless
      # ⭐ now. So the furthest-justified state wins, and the caller compares it
      # against the current one to decide whether anything should move.
      #
      # The exception is a {FAMILIES family}, whose members contents cannot tell
      # apart. Two rules cover it:
      #
      # - **Already inside one** — the current name wins. Re-deriving it would be
      #   a guess dressed up as a correction, and every ⭕ would become 🛑.
      # - **Arriving from outside** — the *weakest* member the contents fit
      #   wins, not the furthest. A 📋 folder whose `plan.md` grew work units
      #   lands on ⭐, not 🟡, because nobody has started. A ✅ folder found
      #   with an open pull request is demonstrably back in the PR phase, and
      #   ⭐ refuses an open pull request, so it lands on 🟡 rather than
      #   claiming 🔴.
      #
      # @return [OpenLanes::Plans::Status, nil] nil when nothing fits at all
      def best_fit
        fitting = STATUSES.select { |s| s.satisfied_by?(subject) }
        return nil if fitting.empty?

        best = PREFERENCE.filter_map { |k| fitting.find { |s| s.key == k } }.first || fitting.first
        return status if self.class.family_of(key).include?(best.key)

        family = self.class.family_of(best.key)
        return best if family.empty?

        floor = family.find { |k| fitting.any? { |s| s.key == k } }
        STATUS_BY_KEY.fetch(floor)
      end

      private

      # The one guard. Entering a state is permitted exactly when that state's
      # invariant holds for this folder's contents.
      #
      # @return [Boolean]
      def justified? = STATUS_BY_KEY.fetch(aasm.to_state).satisfied_by?(subject)

      # @param to [Symbol]
      # @return [String]
      def refusal(to)
        return "#{describe(key)} cannot become #{describe(to)}" unless self.class.edge?(key, to)

        STATUS_BY_KEY.fetch(to).violation(subject)
      end

      # @param key [Symbol]
      # @return [String]
      def describe(key) = STATUS_BY_KEY.fetch(key).to_s

      # The folder moves. {Subject} owns the path, so it owns the move.
      #
      # @return [void]
      def rename! = subject.rename_to(STATUS_BY_KEY.fetch(aasm.to_state))
    end
  end
end
