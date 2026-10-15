# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes resync …`
    module Resync
      # `resync prs` — put an [NNN.MM] prefix on every pull request title.
      class Prs < Base
        desc "Add missing [NNN.MM] prefixes to pull request titles"

        dry_run_option "Retitle nothing; print what would be retitled and adopted"
        option :state,
          default: "all",
          values:  %w[open closed merged all],
          desc:    "Which pull requests to consider"
        option :adopt,
          type:    :boolean,
          default: true,
          desc:    "Mint a retroactive plan folder for every pull request that resolves to none. --no-adopt flags them for a human instead"

        example [
          "-n              # show what would be retitled, and what would be adopted",
          "--state open    # only open pull requests",
          "--no-adopt      # never create a folder; flag the unresolvable ones",
          "                # do it"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          tree = tree_for(options)
          changes = unwrap(OpenLanes::Lifecycle.retitle_prs(tree:,
            github: Vcs.github,
            adopt:  options.fetch(:adopt, true),
            root:   File.dirname(tree.dir),
            commit: !dry_run?(options)))

          if changes.empty?
            success("Every pull request title already carries a prefix.") unless quiet?(options)
            return
          end

          report = Presentation.pr_changes(changes, dry_run: dry_run?(options))
          puts report.lines
          report.report unless quiet?(options)
        end
      end
    end
  end
end
