# frozen_string_literal: true

module OpenLanes
  module CLI
    module ConfigFile
      # `openlanes config move` — the legacy config file into the
      # `.openlanes/` folder, by `git mv` where it is tracked.
      class Move < Base
        desc "Move the legacy config file to #{OpenLanes::Project::FILE}, with git mv so its history follows"

        dry_run_option "Show the move without making it"

        example [
          "      # move it",
          "-n    # show what would move"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          quiet?(options)
          moves = OpenLanes::Setup::ConfigMove.new(root: Dir.pwd).call(dry_run: dry_run?(options))
          return UI.line("Nothing to move: no #{OpenLanes::Project::LEGACY_FILE} here") if moves.empty?

          moves.each { |from, to| puts "#{dry_run?(options) ? "would move" : "moved"} #{from} -> #{to}" }
        rescue OpenLanes::Error => e
          refuse(e.message, 65)
        end
      end
    end
  end
end
