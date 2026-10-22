# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes link` — write the `depends_on:` key into every unfinished
    # spec that has not answered it, through the agent that handles 🔗. Best
    # run on `main` in the primary checkout, which it pulls first: a plan
    # worktree's `.plans` is a snapshot, so keys written there are lost
    # unless that branch merges. Elsewhere it warns and goes on (008.01 D1).
    # It commits nothing.
    class Link < Base
      desc "Write depends_on into the unfinished specs that have not answered it"

      dry_run_option "List the plans that would be linked; pull nothing, invoke no agent"
      option :plans, desc: "Only these plans: NNN or NNN.MM, comma separated"

      example [
        "-n                 # which plans would be linked",
        "--plans 050,051    # only these two"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        tree = tree_for(options)
        root = File.dirname(tree.dir)
        dry_run = dry_run?(options)
        mainline = Vcs.mainline(root:)
        mainline.warnings.each { warn(it) }
        refuse(mainline.note, 69) if !dry_run && mainline.mainline? && !mainline.pull

        linker = OpenLanes::Lifecycle.link(tree:,
          registry: OpenLanes::Agents.registry,
          executor: Execution.executor(root:, dry_run:),
          plans:    options[:plans]&.split(","),
          root:)
        result = linker.call(dry_run:)
        puts(dry_run ? preview(result, linker) : report(result))
        result.cycles.each { error("dependency cycle: #{it.join(" → ")}") }
        exit(result.ok? ? 0 : 1)
      rescue OpenLanes::Error => e
        refuse(e.message, 65)
      end

      private

      # @return [String]
      def preview(result, linker)
        return "No plan is waiting for a link." if result.unchanged.empty?

        result.unchanged.map { "would invoke #{linker.agent.name} for #{it.feature.ordinal}" }.join("\n")
      end

      # The two verdicts `agents/ewoki-linker.md` promises, then any failures.
      #
      # @return [String]
      def report(result)
        lines = if result.linked.empty?
                  ["No new dependencies found."]
                else
                  count = result.linked.size
                  ["#{count} plan#{"s" unless count == 1} linked: #{result.linked.map { it.feature.ordinal }.join(", ")}.",
                   "Their spec.md files changed; commit the current branch to persist."]
                end
        lines += result.failed.map { |subject, note| "failed #{subject.feature.ordinal}: #{note}" }
        lines.join("\n")
      end
    end
  end
end
