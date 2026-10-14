# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes resync …`
    module Resync
      # `resync dirs` — reconcile folder names and places with folder contents.
      class Dirs < Base
        desc "Rename and move plan folders so the name, the place and the contents agree"

        dry_run_option "Rename nothing; print what would be renamed or moved"

        example [
          "-n              # show what would be renamed or moved",
          "                # do it"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          resync = OpenLanes::Lifecycle.resync_dirs(tree: tree_for(options))
          locks = resync.locks
          rewrites = resync.rewrites
          changes = resync.call(commit: !dry_run?(options))

          report_locks(locks, options)
          report_rewrites(rewrites, options)

          if changes.empty? && rewrites.empty?
            unless quiet?(options)
              success("Every folder is already named NNN.MM━━<emoji>━━❯<slug>, in its place, and the emoji matches.")
            end
            return
          end

          changes.each do |change|
            puts "#{change.dirname}\t#{change.target_name}\t#{change.reason}"
            next if quiet?(options)

            say("#{paint(change.dirname, :bright_black)} → #{change.target_name}")
            say("  #{paint(change.reason, :yellow)}", bullet: " ")
          end

          return if quiet?(options)

          total = changes.size + rewrites.size
          if dry_run?(options)
            dry_run_footer(total, "change#{"s" unless total == 1}")
          else
            success("Renamed #{changes.size} folder#{"s" unless changes.size == 1}, " \
                    "rewrote #{rewrites.size} spec#{"s" unless rewrites.size == 1}.")
          end
        end

        private

        # @param rewrites [Array<OpenLanes::Lifecycle::Resync::Dirs::Rewrite>]
        # @param options [Hash]
        # @return [void]
        def report_rewrites(rewrites, options)
          rewrites.each do |rewrite|
            puts "#{rewrite.dirname}/spec.md\t#{rewrite.dirname}/spec.md\t#{rewrite.reason}"
            say("#{rewrite.dirname}/spec.md: #{paint(rewrite.reason, :yellow)}") unless quiet?(options)
          end
        end

        # A lock keeps its folder's name, so a folder that did not move needs
        # a word about why. A dead local lock is cleared by a real run; one
        # from another machine is only ever reported.
        #
        # @param locks [Array<OpenLanes::Lifecycle::Resync::Dirs::HeldLock>]
        # @param options [Hash]
        # @return [void]
        def report_locks(locks, options)
          return if quiet?(options)

          locks.each do |held|
            verdict = if held.foreign? then "another machine's lock; left alone"
                      elsif held.stale? then dry_run?(options) ? "its process is gone; would clear it" : "its process is gone; cleared"
                      else "an agent is working in it; not renamed"
                      end
            say("🔑 #{held}")
            say("  #{paint(verdict, :yellow)}", bullet: " ")
          end
        end
      end
    end
  end
end
