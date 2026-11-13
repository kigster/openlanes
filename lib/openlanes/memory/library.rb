# frozen_string_literal: true

module OpenLanes
  module Memory
    # Every lesson the scopes hold, and every file that could not be read as one.
    #
    # @!attribute [r] lessons
    #   @return [Array<OpenLanes::Memory::Lesson>] one per id, project first
    # @!attribute [r] problems
    #   @return [Array<String>] one line per file skipped, with why
    Library = Data.define(:lessons, :problems) do
      class << self
        # Reads +sources+ in order. The first lesson with an id wins, so a
        # project can overrule a global lesson by reusing its id, and a
        # duplicate id inside one scope is reported rather than silently
        # resolved by file order.
        #
        # @param sources [Array<OpenLanes::Memory::Committed, OpenLanes::Memory::Folder>]
        #   anything with a +name+ and +entries+
        # @return [OpenLanes::Memory::Library]
        def load(sources)
          read = sources.flat_map { |source| source.entries.map { attempt(it, source.name) } }
          lessons, problems = read.partition { it.is_a?(Lesson) }
          kept = lessons.uniq(&:id)
          new(lessons: kept, problems: problems + (lessons - kept).filter_map { duplicate(it, kept) })
        end

        private

        # @param entry [OpenLanes::Memory::Entry, String] a file, or why its source skipped it
        # @return [OpenLanes::Memory::Lesson, String] the lesson, or why the file is not one
        def attempt(entry, scope)
          return entry if entry.is_a?(String)

          Lesson.parse(entry, scope:)
        rescue Lesson::Invalid => e
          e.message
        end

        # A global lesson a project lesson shadows is the point of reusing an
        # id; two in one scope is a mistake worth naming.
        #
        # @return [String, nil]
        def duplicate(lesson, kept)
          taken = kept.find { it.id == lesson.id }
          "#{lesson.path}: id #{lesson.id} is also #{taken.path}" if taken.scope == lesson.scope
        end
      end

      # The active lessons +agent+ follows or checks, addressed to its name,
      # its phase or everyone. The lesson the most plans confirmed comes
      # first, so one that keeps proving itself outlasts a one-off when the
      # budget cuts from the bottom; then severity, the most recently
      # confirmed, and id, so the order is the same on every machine.
      # Retired, graduated and candidate lessons are never shown.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @return [Array<OpenLanes::Memory::Lesson>]
      def for(agent)
        lessons.select { it.active? && (it.for?(agent) || it.checked_by?(agent)) }
               .sort_by { [-it.confirmations, Lesson::SEVERITIES.index(it.severity), -(it.confirmed&.jd || 0), it.id] }
      end
    end
  end
end
