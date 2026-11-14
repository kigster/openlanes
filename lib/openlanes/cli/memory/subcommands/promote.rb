# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory promote`
      class Promote < Base
        desc "Turn waiting lessons into active ones: those seen in #{OpenLanes::Memory::Promotion::THRESHOLD} plans, " \
             "or approved, as a memory pull request a person merges"

        dry_run_option "Write nothing; print what would be promoted, confirmed or left waiting"
        option :local, type: :boolean, default: false, desc: "Write the lesson files into this checkout and open no pull request"
        option :memory, type: :boolean, default: true, desc: "--no-memory (or `memory: false` in .openlanes/config.yml) refuses to promote"

        example [
          "-n      # what would change",
          "        # promote on a branch of its own and open the memory pull request",
          "--local # write the lesson files here, commit nothing"
        ]

        # @return [void]
        def call(**options)
          refuse("Memory is off for this project (`memory: false` or --no-memory): nothing is promoted.", 64) unless options.fetch(:memory, true)

          changes = promote(options)
          changes.each { $stdout.puts(line(it)) }
          moved = changes.count { %i[promote confirm].include?(it.kind) }
          dry_run_footer(moved, "lesson#{"s" unless moved == 1}") if dry_run?(options)
          held_back(changes.select { it.kind == :refuse }.map(&:slug))
        end

        private

        # @return [Array<OpenLanes::Memory::Promotion::Change>]
        def promote(options)
          return OpenLanes::Memory.promotion(root: Dir.pwd).call(commit: !dry_run?(options)) if options[:local] || dry_run?(options)

          published = OpenLanes::Memory.publication(root: Dir.pwd).call
          published.held_back.each { $stdout.puts("held back #{it}") }
          success("memory pull request: #{published.url}") if published.url
          published.changes
        end

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
