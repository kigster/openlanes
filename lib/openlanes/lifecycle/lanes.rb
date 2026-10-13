# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # Moves a plan past the phases its lane skips.
    #
    # A plan in the `plan` lane has a specification its author already
    # trusts, so research and rewriting are skipped: the harness writes the
    # blank `plan.md` yoda-writer would have left and moves the folder to 📋.
    # A plan in the `quick` lane is a short mechanical task: the harness
    # writes a one-unit `plan.md` and moves the folder to ⭐️, where
    # r2d2-mechanic is the only builder that serves the lane.
    #
    # Both moves are ordinary transitions through the state machine, so the
    # invariants still decide; the harness only supplies the file the
    # skipped agent would have written.
    module Lanes
      # The state each lane jumps to.
      TARGET = { plan: :ready_for_planning, quick: :planned }.freeze

      # The states a lane jumps from. Anything later has already been worked.
      FROM = %i[new researched].freeze

      # What the harness writes into `plan.md` for each lane.
      STUB = {
        plan:  "",
        quick: <<~MARKDOWN
          # Plan

          ## Task

          Quick lane: the task is the whole of `spec.md`, done in one pass by `r2d2-mechanic`.
        MARKDOWN
      }.freeze

      module_function

      # Where this plan's lane says it should be, when that is somewhere other
      # than where it is.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param spec [OpenLanes::Plans::Spec]
      # @return [OpenLanes::Plans::Status, nil]
      def target(subject, spec = Plans::Spec.for(subject))
        key = TARGET[spec.lane] or return nil
        return nil unless FROM.include?(subject.status.key)

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

        path = File.join(subject.feature.path, "plan.md")
        unless File.exist?(path)
          File.write(path, [STUB.fetch(spec.lane).rstrip, Completion.markdown(spec)].reject(&:empty?).join("\n\n"))
        end
        machine = subject.machine
        return nil unless machine.may?(to.key)

        machine.promote!(to.key)
        [from, to.key]
      end
    end
  end
end
