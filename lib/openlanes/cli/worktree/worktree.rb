# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes worktree` — create and seed worktrees for plans.
    class Worktree < Base
      desc "Create and seed a worktree for a plan"

      argument :plan,
        required: true,
        desc:     "Plan ordinal (e.g. 002, 002.00, or a plan folder name)"

      option :skip_seed,
        type:    :boolean,
        default: false,
        desc:    "Create the worktree but skip seeding it with .env and credential files"

      example [
        "002                         # create/seed the worktree for plan 002.00",
        "002.01                      # create/seed the worktree for plan 002.01",
        "002.00━━⚪━━❯update-dsl      # find the plan by its folder name",
        "--skip-seed 003             # create the worktree but don't seed it"
      ]

      # @param plan [String] plan identifier
      # @param options [Hash]
      # @return [void]
      def call(plan:, **options)
        tree = tree_for(options)
        is_quiet = quiet?(options)

        feature = resolve_plan(tree, plan)
        unless feature
          refuse("Could not find plan: #{plan}", 66)
        end

        root = File.dirname(tree.dir)
        worktree = OpenLanes::Vcs.worktree(root:)

        checkout = worktree.checkout_for(feature)

        return if is_quiet

        if checkout.created?
          puts("✓ Created worktree for #{feature.ordinal}: #{checkout.path}")
        else
          puts("✓ Using existing worktree for #{feature.ordinal}: #{checkout.path}")
        end

        unless options[:skip_seed]
          seeded = worktree.seed(checkout.path)
          if seeded
            puts("✓ Seeded with .env and credential files")
          else
            warn("⚠ Could not seed worktree, see above for details")
          end
        end

        puts("")
        success("Worktree ready for #{feature.ordinal}")
        puts("Path: #{checkout.path}")
        puts("Branch: #{checkout.branch}")
      end

      private

      # Find the plan that matches the given identifier.
      #
      # @param tree [OpenLanes::Plans::Tree] plans directory wrapper
      # @param plan [String] ordinal, folder name, or slug
      # @return [OpenLanes::Plans::Feature, nil]
      def resolve_plan(tree, plan)
        # Try parsing as an ordinal first
        ordinal = ::OpenLanes::Plans::Ordinal.parse(plan)
        if ordinal
          found = tree.features.find { |f| f.ordinal == ordinal }
          return found if found
        end

        # Try matching by folder name
        tree.features.find { |f| f.dirname == plan }
      end
    end
  end
end
