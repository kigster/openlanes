# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes resync …`
    module Resync
      # `resync dirs` — reconcile folder names with folder contents.
      class Dirs < Base
        desc "Rename plan folders so the name matches the contents and the NNN.MM form"

        dry_run_option "Rename nothing; print what would be renamed"

        example [
          "-n              # show what would be renamed",
          "                # do it"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          changes = OpenLanes::Lifecycle.resync_dirs(tree: tree_for(options))
                                        .call(commit: !dry_run?(options))

          if changes.empty?
            success("Every folder is already named NNN.MM-<emoji> → <slug> and the emoji matches.") unless quiet?(options)
            return
          end

          changes.each do |change|
            puts "#{change.dirname}\t#{File.basename(change.target)}\t#{change.reason}"
            next if quiet?(options)

            say("#{paint(change.dirname, :bright_black)} → #{File.basename(change.target)}")
            say("  #{paint(change.reason, :yellow)}", bullet: " ")
          end

          return if quiet?(options)

          if dry_run?(options)
            dry_run_footer(changes.size, "rename#{"s" unless changes.size == 1}")
          else
            success("Renamed #{changes.size} folder#{"s" unless changes.size == 1}.")
          end
        end
      end
    end
  end
end
