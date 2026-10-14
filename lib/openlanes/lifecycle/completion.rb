# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # Copies the spec's `task-completed-when` and how to test it into
    # `plan.md`, so the builders and the reviewer read them in the document
    # they work from rather than only in the frontmatter of another one.
    #
    # An agent is asked to copy them; the harness checks. A planner that
    # paraphrased them, or forgot, would leave the criteria in the one place
    # the reviewer was not looking, so a missing section is appended after the
    # agent signs, and a section the agent wrote is never touched.
    module Completion
      COMPLETED_WHEN_HEADING = "## Task completed when"
      HOW_TO_TEST = "## How to test"

      # The heading {HOW_TO_TEST} replaced. A plan.md written before the
      # rename still carries it, and without recognising it the harness would
      # append a second copy of the same steps under the new name.
      FORMER_HOW_TO_TEST = "## How to verify"

      module_function

      # The sections for the spec's criteria, in the order a reader needs them.
      #
      # @param spec [OpenLanes::Plans::Spec]
      # @param present [String] the plan's current text; sections it already
      #   has are left out
      # @return [String] empty when the spec says nothing, or the plan has it
      def markdown(spec, present: "")
        [
          section(COMPLETED_WHEN_HEADING, spec.completed_when, present),
          section(HOW_TO_TEST, spec.how_to_test, present, also: FORMER_HOW_TO_TEST)
        ].compact.join("\n")
      end

      # Append whatever `plan.md` is missing. Writes nothing when it is
      # complete, so it is safe after every round.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean] whether the file changed
      def copy(subject)
        path = File.join(subject.feature.path, "plan.md")
        return false unless File.file?(path)

        text = File.read(path, encoding: "UTF-8")
        missing = markdown(Plans::Spec.for(subject), present: text)
        return false if missing.empty?

        File.write(path, "#{text.rstrip}\n\n#{missing}")
        true
      end

      # @param also [String, nil] an older heading that counts as present
      # @return [String, nil]
      def section(heading, items, present, also: nil)
        return nil if items.empty? || [heading, also].compact.any? { present.match?(/^#{Regexp.escape(it)}\s*$/i) }

        "#{heading}\n\n#{items.map { Plans::Spec.list_item(it) }.join("\n")}\n"
      end
      private_class_method :section
    end
  end
end
