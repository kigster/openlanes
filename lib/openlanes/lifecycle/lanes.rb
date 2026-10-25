# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # Moves a plan past the phases before where it starts.
    #
    # `planning` has a specification its author already trusts, so research
    # and rewriting are skipped: the harness writes the blank `plan.md`
    # yoda-writer would have left and moves the folder to 📋, where the
    # planner answers `depends_on:` while it plans. `building` is a short
    # mechanical task: the harness writes a one-unit `plan.md` in the
    # planner's place and moves it straight to ⭐, where r2d2-mechanic is the
    # only builder. It never rests at 📋, where the planner would be assigned
    # before the next hop. Nobody answers `depends_on:` for it unless its
    # author did, and an absent key waits for nothing.
    #
    # Every move is an ordinary transition through the state machine, so the
    # invariants still decide; the harness only supplies the file the
    # skipped agent would have written.
    module Lanes
      # Where each starts value jumps, from each state it jumps from.
      # `research` does not jump. Anything later has already been worked.
      HOPS = {
        planning: { new: :ready_for_planning, researched: :ready_for_planning },
        building: { new: :planned, researched: :planned, ready_for_planning: :planned }
      }.freeze

      # What the harness writes into `plan.md` for a `building` plan's ⭐.
      QUICK_PLAN = <<~MARKDOWN
        # Plan

        ## Task

        Starts at building: the task is the whole of `spec.md`, done in one pass by `r2d2-mechanic`.
      MARKDOWN

      module_function

      # Where this plan's `starts:` says it should be, when that is somewhere other
      # than where it is.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param spec [OpenLanes::Plans::Spec]
      # @return [OpenLanes::Plans::Status, nil]
      def target(subject, spec = Plans::Spec.for(subject))
        key = HOPS.dig(spec.starts, subject.status.key) or return nil
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

      # 📋 gets the blank `plan.md` yoda-writer leaves; a `building` plan's ⭐
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
