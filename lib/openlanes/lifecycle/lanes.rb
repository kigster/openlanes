# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # Moves a plan past the phases its lane skips. Every lane passes through
    # 🔗, so ewoki-linker answers `depends_on:` before anyone plans or builds.
    #
    # A plan in the `plan` lane has a specification its author already
    # trusts, so research and rewriting are skipped: the harness writes the
    # blank `plan.md` yoda-writer would have left and moves the folder to 🔗.
    # A plan in the `quick` lane is a short mechanical task: it goes to 🔗
    # the same way, and once linked (📋) the harness writes a one-unit
    # `plan.md` in the planner's place and moves it to ⭐, where r2d2-mechanic
    # is the only builder that serves the lane.
    #
    # Every move is an ordinary transition through the state machine, so the
    # invariants still decide; the harness only supplies the file the
    # skipped agent would have written.
    module Lanes
      # Where each lane jumps, from each state it jumps from. Anything later
      # has already been worked.
      HOPS = {
        plan:  { new: :ready_for_linking, researched: :ready_for_linking },
        quick: { new: :ready_for_linking, researched: :ready_for_linking, ready_for_planning: :planned }
      }.freeze

      # What the harness writes into `plan.md` for the quick lane's ⭐.
      QUICK_PLAN = <<~MARKDOWN
        # Plan

        ## Task

        Quick lane: the task is the whole of `spec.md`, done in one pass by `r2d2-mechanic`.
      MARKDOWN

      module_function

      # Where this plan's lane says it should be, when that is somewhere other
      # than where it is.
      #
      # A quick-lane plan whose author already wrote `plan.md` cannot sit at
      # 🔗, which needs it blank, so it goes to ⭐ as it always did.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param spec [OpenLanes::Plans::Spec]
      # @return [OpenLanes::Plans::Status, nil]
      def target(subject, spec = Plans::Spec.for(subject))
        key = HOPS.dig(spec.lane, subject.status.key) or return nil
        key = :planned if spec.lane == :quick && key == :ready_for_linking && authored?(subject)
        Plans.status(key)
      end

      # Write the skipped agent's file and move the folder.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param commit [Boolean] false only reports what would happen
      # @return [Array(Symbol, Symbol), nil] from and to, when it moved
      def advance(subject, commit:)
        spec = Plans::Spec.for(subject)
        to = target(subject, spec) or return nil
        from = subject.status.key
        return [from, to.key] unless commit

        write_plan(subject, spec, to.key)
        machine = subject.reread!.machine
        landing = machine.onward(to.key)
        return nil unless machine.may?(landing)

        machine.promote!(landing)
        [from, landing]
      end

      # 🔗 gets the blank `plan.md` yoda-writer leaves; the quick lane's ⭐
      # gets {QUICK_PLAN} and the spec's completion criteria, over a blank
      # one. A `plan.md` the author wrote is never replaced.
      #
      # @return [void]
      def write_plan(subject, spec, to)
        path = File.join(subject.feature.path, "plan.md")
        return if authored?(subject)

        body = to == :planned ? [QUICK_PLAN.rstrip, Completion.markdown(spec)].reject(&:empty?).join("\n\n") : ""
        File.write(path, body) if to == :planned || !File.exist?(path)
      end

      # @return [Boolean] whether `plan.md` holds a plan someone wrote
      def authored?(subject)
        subject.file?("plan.md") && Plans::PLAN_HEADING.match?(Plans::Ledger.stripped(subject.read("plan.md")))
      end
    end
  end
end
