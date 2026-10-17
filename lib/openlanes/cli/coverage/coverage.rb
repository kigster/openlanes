# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes coverage PLAN` — the coverage gate (M15), by hand.
    #
    # Runs the declared test command in the plan's worktree, never in the main
    # tree, and prints the verdict `ready-to-merge` will wait on. The verdict is
    # the deliverable and goes to STDOUT; the command's own output, when the
    # gate withholds, goes to STDERR. Exits 1 when the gate withholds, so a
    # script or CI step can stop on it.
    #
    # `CLI::Coverage` shadows the library's namespace, so this file names
    # `OpenLanes::Coverage` in full.
    class Coverage < Base
      desc "Run a plan's declared test command in its worktree and check line coverage"

      argument :plan, required: true, desc: "Plan ordinal: NNN or NNN.MM"

      dry_run_option "Print the declaration and where the command would run; run nothing"

      example [
        "013                  # run .openlanes.coverage.yml's command in plan 013's worktree",
        "013 --dry-run        # show what would run, and where"
      ]

      # @param plan [String]
      # @param options [Hash]
      # @return [void]
      def call(plan:, **options)
        tree = tree_for(options)
        ordinal = Plans::Ordinal.parse(plan.to_s)
        subject = ordinal && tree.find(ordinal)
        refuse("No plan #{plan} in #{tree.dir}.\n\nKnown: #{tree.ordinals.join(", ")}", 66) unless subject

        worktree = OpenLanes::Vcs.worktree(root: File.dirname(tree.dir))
        refuse("#{worktree.root} is not a git repository; the gate runs in a plan's worktree.", 66) unless worktree.repository?

        return preview(worktree, subject.feature) if dry_run?(options)

        verdict = OpenLanes::Engine.coverage_gate.call(checkout: worktree.checkout_for(subject.feature))
        $stdout.puts(verdict.to_s)
        return if verdict.passed?

        warn(verdict.output.join("\n")) unless verdict.output.empty?
        exit 1
      end

      private

      # @return [void]
      def preview(worktree, feature)
        path = worktree.path_for(feature)
        config = File.directory?(path) && OpenLanes::Coverage.config(path)
        $stdout.puts("would run in #{path}")
        if config
          $stdout.puts("  #{config.command}", "  then read #{config.report} (#{config.format}), minimum #{format("%g%%", config.minimum)}")
        else
          $stdout.puts("  the declaration is read from #{OpenLanes::Coverage::Config::FILE} there once the worktree exists")
        end
        dry_run_footer(1, "coverage run")
      rescue OpenLanes::Coverage::Invalid => e
        refuse(e.message, 65)
      end
    end
  end
end
