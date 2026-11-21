# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory report` — per lesson, how many plans it was offered
      # on and how many cited it, counted from the event log (decision C5).
      #
      # With the log off there is no count to give, and the command says so
      # rather than printing zeros: a column of zeros reads as "every lesson
      # was ignored", which is exactly the evidence retirement acts on.
      #
      # STDOUT carries the table; skipped lesson files go to STDERR.
      class Report < Base
        desc "Show, per lesson, how many plans it was offered on and cited on, from the event log"

        # The columns of the report, left to right.
        HEADER = %w[ID TITLE OFFERED CITED LAST_CITED].freeze

        # Said instead of a table when the event log is off.
        UNAVAILABLE = "Citation counts are unavailable: events are off. Set `events: { enabled: true }` in " \
                      "#{OpenLanes::Project::FILE} to record which lessons agents are offered and cite.".freeze

        example ["                           # every lesson, with its offers and citations"]

        # @return [void]
        def call(**)
          root = Dir.pwd
          library = OpenLanes::Memory.library(root:)
          library.problems.each { warn("skipped #{it}") }
          usage = OpenLanes::Memory.uptake(root:) or refuse(UNAVAILABLE, 78)
          $stdout.write(table(library.lessons, usage))
        end

        private

        # @param lessons [Array<OpenLanes::Memory::Lesson>]
        # @param usage [Hash{String => OpenLanes::Events::LessonUsage}]
        # @return [String]
        def table(lessons, usage)
          return "No lessons yet, so nothing to count.\n" if lessons.empty?

          Table.render([HEADER, *lessons.map { row(it, usage[it.id] || OpenLanes::Events::LessonUsage.unseen(it.id)) }])
        end

        # @param lesson [OpenLanes::Memory::Lesson]
        # @param seen [OpenLanes::Events::LessonUsage]
        # @return [Array<String>]
        def row(lesson, seen)
          [lesson.id, lesson.title, seen.offered.to_s, seen.cited.to_s, seen.last_cited.to_s[0, 10].then { it.empty? ? "never" : it }]
        end
      end
    end
  end
end
