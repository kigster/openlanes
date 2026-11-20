# frozen_string_literal: true

module OpenLanes
  module Memory
    # The lessons the next memory pull request proposes to retire: active,
    # offered on {THRESHOLD} plans or more, and cited on none (decision C5).
    #
    # A proposal, never a change. Nothing here edits a lesson file: the pull
    # request lists them and a person retires one by setting `status:
    # retired` before merging, or leaves it. Graduation (a lesson becoming a
    # check, a rule or an eval case) is a person's call for the same reason.
    class Retirement
      # Plans a lesson must have been offered on, uncited, before it is
      # proposed. Below it a lesson may simply not have met its work yet.
      THRESHOLD = 15

      # One lesson proposed for retirement.
      #
      # @!attribute [r] id
      #   @return [String]
      # @!attribute [r] title
      #   @return [String]
      # @!attribute [r] offered
      #   @return [Integer] plans it was offered on
      Proposal = Data.define(:id, :title, :offered) do
        # @return [String] one line of the pull request body
        def to_s = "- #{id} #{title}: offered on #{offered} plans, cited on none"
      end

      # Proposed, not applied: the pull request changes no lesson it lists
      # here. Retiring one is a person's edit on that branch before the merge.
      #
      # @param proposals [Array<OpenLanes::Memory::Retirement::Proposal>]
      # @return [String] the pull request body's section; empty when nothing is proposed
      def self.section(proposals)
        return "" if proposals.empty?

        "\n### Proposed for retirement\n\nOffered on #{THRESHOLD} or more plans and cited on none. " \
          "To retire one, set `status: retired` in its file on this branch before merging; merging without that changes nothing.\n\n" \
          "#{proposals.join("\n")}\n"
      end

      # @param usage [Hash{String => OpenLanes::Events::LessonUsage}, nil] from {Uptake.read}; nil proposes nothing
      # @param threshold [Integer]
      def initialize(usage, threshold: THRESHOLD)
        @usage = usage || {}
        @threshold = threshold
      end

      # @param lessons [Array<OpenLanes::Memory::Lesson>]
      # @return [Array<OpenLanes::Memory::Retirement::Proposal>] in the order given
      def call(lessons)
        lessons.filter_map do |lesson|
          seen = @usage[lesson.id]
          next unless lesson.active? && seen && seen.offered >= @threshold && seen.cited.zero?

          Proposal.new(id: lesson.id, title: lesson.title, offered: seen.offered)
        end
      end
    end
  end
end
