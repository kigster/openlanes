# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory curate`
      class Curate < Base
        desc "Have the curator read finished or rejected plans and propose lessons into #{OpenLanes::Memory::INBOX_DIR}"

        argument :plans, type: :array, required: true, desc: "Which plans to learn from: NNN or NNN.MM, e.g. 056 060.01"

        dry_run_option "Invoke no agent; name the plans that would be read"
        option :agent, default: OpenLanes::Memory::Curation::DEFAULT_AGENT, desc: "Hand the plans to a different agent"

        example [
          "056          # propose lessons from plan 056",
          "056 060 -n   # name what would be read"
        ]

        # @return [void]
        def call(plans:, **options)
          curation = OpenLanes::Memory.curation(root: Dir.pwd, agent: agent(options), dry_run: dry_run?(options))
          subjects = subjects(plans, tree_for(options))
          credentials_warning unless dry_run?(options)
          failed = subjects.map { curation.call(it) }.each { report(it) }.reject(&:ok)
          refuse("#{failed.map(&:ordinal).join(", ")}: the curator did not finish.", 1) unless failed.empty?
        end

        private

        # @return [OpenLanes::Agents::Agent]
        def agent(options)
          name = options.fetch(:agent, OpenLanes::Memory::Curation::DEFAULT_AGENT)
          OpenLanes::Agents.find(name) or refuse("No agent named #{name}. `openlanes agents list` names them.", 64)
        end

        # @return [Array<OpenLanes::Plans::Subject>]
        def subjects(plans, tree)
          plans.flat_map { it.split(",") }.map { tree.find(it) or refuse("There is no plan #{it}.", 66) }
        end

        # @param report [OpenLanes::Memory::Curation::Report]
        # @return [void]
        def report(report)
          return warn("#{report.ordinal}: #{report.note}") if report.outcomes.empty?

          report.outcomes.each do |outcome|
            $stdout.puts("#{report.ordinal}  #{outcome.status.to_s.ljust(10)}#{outcome.slug}#{": #{outcome.reason}" if outcome.reason}")
          end
        end
      end
    end
  end
end
