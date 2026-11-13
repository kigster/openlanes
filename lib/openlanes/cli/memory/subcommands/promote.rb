# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory promote`
      class Promote < Base
        desc "Turn waiting lessons into active ones: those seen in #{OpenLanes::Memory::Promotion::THRESHOLD} plans, " \
             "or approved. Writes files only; agents see a lesson once it is merged"

        dry_run_option "Write nothing; print what would be promoted, confirmed or left waiting"

        example [
          "-n      # what would change",
          "        # write the lesson files, then commit them and open a pull request"
        ]

        # @return [void]
        def call(**options)
          changes = OpenLanes::Memory.promotion(root: Dir.pwd).call(commit: !dry_run?(options))
          changes.each { $stdout.puts(line(it)) }
          moved = changes.count { %i[promote confirm].include?(it.kind) }
          dry_run_footer(moved, "lesson#{"s" unless moved == 1}") if dry_run?(options)
          held_back(changes.select { it.kind == :refuse }.map(&:slug))
        end

        private

        # @param slugs [Array<String>] candidates the secret scan stopped
        # @return [void]
        def held_back(slugs)
          refuse("#{slugs.size} held back: reword #{slugs.join(", ")} in the inbox and promote again.", 65) unless slugs.empty?
        end

        # @param change [OpenLanes::Memory::Promotion::Change]
        # @return [String]
        def line(change)
          name = [change.id, change.slug].compact.uniq.join(" ")
          "#{change.kind.to_s.ljust(8)}#{name}: #{change.why}"
        end
      end
    end
  end
end
