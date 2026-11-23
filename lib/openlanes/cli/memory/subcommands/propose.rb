# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory propose` — file a lesson into the inbox by hand, or
      # from an agent working outside a run.
      #
      # The proposal goes through {OpenLanes::Memory.file}, the path the
      # curator's answer takes, so it meets the same checks: the fields a
      # proposal needs, the slug, the secret scan, the instruction-text check
      # and {OpenLanes::Memory::Lesson.parse}. A slug already waiting gains
      # one more sighting and keeps its words; nothing is overwritten.
      #
      # STDOUT carries one line per proposal, and on a dry run the file that
      # would be written; a refusal names the check and exits 65.
      class Propose < Base
        desc "File a lesson into #{OpenLanes::Memory::INBOX_DIR} through the checks the curator's proposals pass"

        argument :slug, required: false, desc: "Lower-case words joined by `-`, or an existing lesson's id or waiting slug"

        option :title, desc: "One line, under 200 characters, an instruction a stranger could follow"
        option :body, desc: "Two to five sentences: why, and what to do instead"
        option :finding, desc: "One line of evidence: what happened, and where"
        option :applies_to, type: :array, desc: "Agent names or phases that should follow it, comma-separated, or `all`"
        option :checked_by, type: :array, desc: "Reviewers or phases that should cite it when it is broken"
        option :kind, desc: "practice, pitfall, decision or struck"
        option :severity, desc: "high, medium or low"
        option :plan, desc: "The plan it was learnt on, NNN or NNN.MM; left out, the sighting counts toward no promotion"
        option :from, desc: "Read the proposal from FILE (`-` for STDIN): a lesson file, or the curator's JSON lines"
        dry_run_option "Check it and print the file that would be written; write nothing"

        example [
          "real-plan-trees --title 'Build real trees in specs' --applies-to build --finding '…' --body '…' --plan 056",
          "--from candidate.md -n      # check a lesson file and show what would be filed",
          "--from - --plan 060 < said.txt   # the curator's JSON lines, from STDIN"
        ]

        # How a dry run words each outcome: what would happen, not what did.
        PREVIEW = { added: :add, confirmed: :confirm, dropped: :refused }.freeze

        # The flags that carry a proposal's fields, by the key a proposal reads.
        FIELDS = %i[slug title body finding applies_to checked_by kind severity].freeze

        # @return [void]
        def call(**options)
          outcomes = OpenLanes::Memory.file(reads(options), plan: plan(options[:plan]), root: Dir.pwd, dry_run: dry_run?(options))
          outcomes.each { report(it, dry_run?(options)) }
          refused(outcomes.select { it.status == :dropped })
          filed = outcomes.count { %i[added confirmed].include?(it.status) }
          dry_run_footer(filed, "proposal#{"s" unless filed == 1}") if dry_run?(options)
        end

        private

        # @param dropped [Array<OpenLanes::Memory::Inbox::Outcome>]
        # @return [void] exits 65 when anything was dropped
        def refused(dropped)
          return if dropped.empty?

          refuse("#{dropped.size} refused: #{dropped.map { "#{it.slug || "proposal"} (#{it.check})" }.join(", ")}.", 65)
        end

        # @return [Array<OpenLanes::Memory::Proposal, OpenLanes::Memory::Proposal::Rejection>]
        def reads(options)
          given = FIELDS.select { options[it] }
          return [OpenLanes::Memory::Proposal.build(fields(options))] unless options[:from]

          refuse("Give the fields as flags or in --from, not both (#{given.map { "--#{it.to_s.tr("_", "-")}" }.join(", ")}).", 64) if given.any?
          text = source(options[:from])
          said = OpenLanes::Memory::Proposal.scan(text)
          said.empty? ? [OpenLanes::Memory::Proposal.markdown(text)] : said
        end

        # @return [Hash{String => Object}]
        def fields(options) = FIELDS.to_h { [it.to_s, options[it]] }.compact

        # @return [String]
        def source(from)
          from == "-" ? $stdin.read : File.read(from)
        rescue SystemCallError => e
          refuse("Cannot read #{from}: #{e.message}", 66)
        end

        # The canonical NNN.MM, so `56` and `056.00` are one plan's sighting.
        #
        # @return [String, nil]
        def plan(word)
          return if word.nil?

          OpenLanes::Plans::Ordinal.parse(word)&.to_s or refuse("#{word} is not a plan number: NNN or NNN.MM.", 64)
        end

        # @param outcome [OpenLanes::Memory::Inbox::Outcome]
        # @return [void]
        def report(outcome, dry_run)
          status = (dry_run || outcome.status == :dropped ? PREVIEW.fetch(outcome.status, outcome.status) : outcome.status).to_s
          why = outcome.reason ? ": #{outcome.check} check: #{outcome.reason}" : ""
          $stdout.puts("#{status.ljust(10)}#{outcome.slug}#{why}")
          $stdout.write(outcome.text) if dry_run && outcome.text
        end
      end
    end
  end
end
