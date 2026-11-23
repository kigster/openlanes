# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory inbox` — and with `--global`, the candidates in the
      # operator's own store, waiting for a second project to hold them (C3).
      # Read only: the global store is written by the run's mirror, never here.
      class Inbox < Base
        desc "List the lessons waiting in #{OpenLanes::Memory::INBOX_DIR}, and the plans each was seen in"

        HEADER = %w[SLUG PLANS APPROVED FOR TITLE].freeze

        # The columns of `--global`.
        GLOBAL_HEADER = %w[SLUG PROJECTS FOR TITLE].freeze

        option :global,
          type:    :boolean,
          default: false,
          desc:    "List the global candidates, mirrored from your projects' merged lessons, and the projects each came from"

        # @param options [Hash]
        # @return [void]
        def call(**options)
          return global if options[:global]

          waiting = OpenLanes::Memory.inbox(root: Dir.pwd).candidates
          return $stdout.write("Nothing is waiting. `openlanes memory curate NNN` proposes lessons from a plan.\n") if waiting.empty?

          $stdout.write(Table.render([HEADER, *waiting.map { row(it) }]))
        end

        private

        # @return [void]
        def global
          waiting = OpenLanes::Memory.global_store.candidates
          return $stdout.write("No global candidate. A run mirrors each project's merged lessons here.\n") if waiting.empty?

          rows = waiting.map do |candidate|
            [candidate.slug, OpenLanes::Memory::GlobalStore.projects(candidate).join(","), Array(candidate.meta["applies_to"]).join(","), candidate.title]
          end
          $stdout.write(Table.render([GLOBAL_HEADER, *rows]))
        end

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
