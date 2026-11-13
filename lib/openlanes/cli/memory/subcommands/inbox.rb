# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory inbox`
      class Inbox < Base
        desc "List the lessons waiting in #{OpenLanes::Memory::INBOX_DIR}, and the plans each was seen in"

        HEADER = %w[SLUG PLANS APPROVED FOR TITLE].freeze

        # @return [void]
        def call(**)
          waiting = OpenLanes::Memory.inbox(root: Dir.pwd).candidates
          return $stdout.write("Nothing is waiting. `openlanes memory curate NNN` proposes lessons from a plan.\n") if waiting.empty?

          $stdout.write(Table.render([HEADER, *waiting.map { row(it) }]))
        end

        private

        # @param candidate [OpenLanes::Memory::Candidate]
        # @return [Array<String>]
        def row(candidate)
          [candidate.slug, candidate.plans.join(","), candidate.approved? ? "yes" : "", Array(candidate.meta["applies_to"]).join(","),
           candidate.title]
        end
      end
    end
  end
end
