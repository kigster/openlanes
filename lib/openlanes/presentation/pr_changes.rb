# frozen_string_literal: true

module OpenLanes
  module Presentation
    # What `resync prs` did, or would do, to pull request titles: one tab-
    # separated row per change for STDOUT, and the retitles, the new plan
    # folders, the skipped pull requests and the assumed-prefix warning for
    # a person on STDERR.
    class PrChanges
      include UI

      # @param changes [Array<OpenLanes::Lifecycle::Resync::Prs::Change>]
      # @param dry_run [Boolean] whether nothing was actually changed
      def initialize(changes, dry_run:)
        @changes = changes
        @dry_run = dry_run
      end

      # @return [Array<String>] the deliverable rows: number, new title, reason
      def lines = @changes.map { |change| "#{change.number}\t#{change.new_title || "-"}\t#{change.reason}" }

      # Draws the report on STDERR.
      #
      # @return [void]
      def report
        applicable, flagged = @changes.partition(&:applicable?)
        assumed = applicable.select(&:assumed?)

        applicable.each { |change| say("##{change.number}  #{change.new_title}#{note(change)}") }
        adoptions(applicable.select(&:adopted?))
        flagged.each { |change| say("##{change.number}  #{paint("SKIPPED", :red)} — #{change.reason}", bullet: "!") }
        footer(applicable.size)
        assumptions(assumed)
      end

      private

      # @param change [OpenLanes::Lifecycle::Resync::Prs::Change]
      # @return [String, nil]
      def note(change)
        if change.adopted?
          paint("   (new plan)", :magenta)
        elsif change.assumed?
          paint("   (assumed)", :yellow)
        end
      end

      # Creating folders is a bigger act than editing a title, so it is
      # reported separately rather than buried in the retitle list.
      #
      # @param adopted [Array<OpenLanes::Lifecycle::Resync::Prs::Change>]
      # @return [void]
      def adoptions(adopted)
        return if adopted.empty?

        verb = @dry_run ? "Would create" : "Created"
        info("#{verb} #{adopted.size} plan folder#{"s" unless adopted.size == 1} for pull " \
             "requests that resolved to no plan:\n\n" \
             "#{adopted.map { |c| "  #{c.ordinal}  ##{c.number}  #{c.title}" }.join("\n")}\n\n" \
             "Each holds its pull request and nothing else. Run `openlanes run`\n" \
             "to have the specification written from what the pull request actually did.")
      end

      # @param count [Integer] titles retitled, or that would be
      # @return [void]
      def footer(count)
        if @dry_run
          return if count.zero?

          warn("#{count} retitle#{"s" unless count == 1} pending — nothing was changed.\n" \
               "Re-run without --dry-run to apply.")
        else
          success("Retitled #{count} pull request#{"s" unless count == 1}.")
        end
      end

      # @param assumed [Array<OpenLanes::Lifecycle::Resync::Prs::Change>]
      # @return [void]
      def assumptions(assumed)
        return if assumed.empty?

        warn("#{assumed.size} title#{"s" unless assumed.size == 1} would get " \
             "[#{OpenLanes::NO_PLAN_PREFIX}] because no plan resolved.\n\n" \
             "That is an assertion about intent, and it is yours to make: check each one\n" \
             "before committing. A pull request that writes a plan's spec belongs to that\n" \
             "plan however its branch was named.")
      end
    end
  end
end
