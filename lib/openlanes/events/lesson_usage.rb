# frozen_string_literal: true

module OpenLanes
  module Events
    # How one lesson has fared, counted from `lesson_offered` and
    # `lesson_cited` (decision C5).
    #
    # Derived on every ask and never stored, for {PlanSpend}'s reason: a
    # `usage.json` kept beside the log would be a second copy that drifts the
    # first time a node's file arrives late. Counts are of distinct plans, not
    # invocations: a lesson offered to every round of one long plan has been
    # tried on one piece of work, and retirement asks how many pieces of work
    # passed it by.
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] offered
    #   @return [Integer] plans whose prompts carried it
    # @!attribute [r] cited
    #   @return [Integer] plans whose reports named it
    # @!attribute [r] last_cited
    #   @return [String, nil] ISO 8601 of the latest citation
    LessonUsage = Data.define(:id, :offered, :cited, :last_cited)

    class LessonUsage
      # The kinds this counts.
      OFFERED = "lesson_offered"
      CITED = "lesson_cited"

      class << self
        # @param events [Array<OpenLanes::Events::Event>] already deduplicated
        # @param project [String, nil] only this project's events; nil counts every project
        # @return [Hash{String => OpenLanes::Events::LessonUsage}] by lesson id
        def tally(events, project: nil)
          mine = events.select { [OFFERED, CITED].include?(it.kind) && (project.nil? || it.project == project) }
          mine.group_by { it.payload["lesson"].to_s }.to_h { |id, seen| [id, of(id, seen)] }
        end

        # @param id [String]
        # @return [OpenLanes::Events::LessonUsage] a lesson the log never saw
        def unseen(id) = new(id:, offered: 0, cited: 0, last_cited: nil)

        private

        def of(id, seen)
          offers, citations = seen.partition { it.kind == OFFERED }
          new(id:, offered: plans(offers), cited: plans(citations), last_cited: citations.map(&:at).max)
        end

        # A plan is its project and ordinal: two projects sharing one log
        # directory each have a `001.00`.
        def plans(events) = events.map { [it.project, it.plan] }.uniq.size
      end
    end
  end
end
