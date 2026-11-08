# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes memory …` — the lessons agents are told (docs/continuous-learning.md).
    module Memory
      # `openlanes memory list` — every lesson both scopes hold, or, with
      # `--agent`, the exact section that agent's prompt would carry.
      #
      # STDOUT carries the list; files that could not be read as lessons are
      # warned about on STDERR, so the list stays pipeable.
      class List < Base
        desc "List the lessons in #{OpenLanes::Memory::PROJECT_DIR} and your global memory, " \
             "or with --agent, the section that agent's prompt carries"

        # The columns of the list, left to right.
        HEADER = %w[ID SCOPE STATUS SEVERITY FOR CHECKED_BY TITLE].freeze

        option :agent, desc: "Print the section this agent's prompt would carry, e.g. --agent backend-coder"

        example [
          "                           # every lesson, project and global",
          "--agent staff-reviewer     # what staff-reviewer is told"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          library = OpenLanes::Memory.library(root: Dir.pwd)
          library.problems.each { warn("skipped #{it}") }
          return $stdout.write(table(library.lessons)) unless options[:agent]

          agent = OpenLanes::Agents.find(options[:agent]) or
            refuse("No agent named #{options[:agent]}. `openlanes agents list` names them.", 64)
          section = OpenLanes::Memory.section(agent:, root: Dir.pwd)
          $stdout.write(section.empty? ? "No active lesson is for #{agent.name}.\n" : section)
        end

        private

        # @param lessons [Array<OpenLanes::Memory::Lesson>]
        # @return [String]
        def table(lessons)
          return "No lessons yet. Write one per file under #{OpenLanes::Memory::PROJECT_DIR}/.\n" if lessons.empty?

          rows = [HEADER, *lessons.map { row(it) }]
          widths = HEADER.each_index.map { |i| rows.map { it[i].size }.max }
          "#{rows.map { |cells| cells.zip(widths).map { |cell, width| cell.ljust(width) }.join("  ").rstrip }.join("\n")}\n"
        end

        # @param lesson [OpenLanes::Memory::Lesson]
        # @return [Array<String>]
        def row(lesson)
          [lesson.id, lesson.scope, lesson.status, lesson.severity, lesson.applies_to.join(","), lesson.checked_by.join(","),
           lesson.title].map(&:to_s)
        end
      end
    end
  end
end
