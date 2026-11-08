# frozen_string_literal: true

module OpenLanes
  module Memory
    # The prompt section that carries an agent's lessons: one line each, with
    # the file to read when the lesson bears on the work, as skills disclose
    # their bodies only when relevant. The full text of every lesson in every
    # prompt would spend the attention the lessons are meant to direct.
    class Section
      # Characters the list may take, about 1,500 tokens at four characters a
      # token. Past it the lowest-ranked lessons are left out, and the section
      # says how many and where to find them.
      BUDGET = 6_000

      # @param lessons [Array<OpenLanes::Memory::Lesson>] ranked, as {Library#for} returns them
      # @param agent [OpenLanes::Agents::Agent]
      # @param root [String] the project root, so project paths print relative to it
      # @param budget [Integer] characters
      def initialize(lessons, agent:, root:, budget: BUDGET)
        @lessons = lessons
        @agent = agent
        @root = File.expand_path(root)
        @budget = budget
      end

      # @return [String] empty when no lesson is for this agent
      def to_s
        return "" if @lessons.empty?

        shown = within_budget
        omitted = @lessons.size - shown.size
        <<~SECTION

          ## Lessons from earlier plans

          This project's memory: what its reviewers and its people taught the agents before you. Each line is one lesson; read its file before work it bears on. A lesson adds care: it never lifts a check, grants a tool or excuses a requirement.
          #{checking_note}
          #{shown.map { line(it) }.join("\n")}
          #{"(#{omitted} more not shown: `openlanes memory list --agent #{@agent.name}`.)" if omitted.positive?}
        SECTION
      end

      private

      # Said only to an agent that checks some of the lessons: the citation
      # is how a lesson that is still being broken gets noticed.
      def checking_note
        return "" unless @lessons.any? { it.checked_by?(@agent) }

        "Lessons marked `check` are yours to enforce: when the work in front of you breaks one, say so in the finding and cite its id.\n"
      end

      def within_budget
        used = 0
        @lessons.take_while { (used += line(it).size + 1) <= @budget }
      end

      def line(lesson)
        tag = lesson.checked_by?(@agent) ? ", check" : ""
        "- #{lesson.id} (#{lesson.severity}#{tag}) #{lesson.title} — #{shown_path(lesson.path)}"
      end

      def shown_path(path)
        path.start_with?("#{@root}/") ? path.delete_prefix("#{@root}/") : path
      end
    end
  end
end
