# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes skills …`
    module Skills
      # `skills install` — copy the bundled skills where agents look for them.
      class Install < Base
        standalone!

        SUMMARY = "Copy the skills bundled with this gem into a skill directory"

        # The help screen lists what is bundled, read from each SKILL.md when
        # the help renders, so a skill added to `skills/` shows up here
        # without anybody editing this command. One paragraph per skill,
        # because dry-cli-help reflows paragraphs to the terminal's width.
        #
        # The `skills` group screen asks for the same description to fill one
        # row of its command list, where five paragraphs would bury the row;
        # it gets the summary alone.
        #
        # @return [String]
        def self.description
          skills = OpenLanes::Skills.bundled
          return SUMMARY if skills.empty? || listing?

          rows = skills.map do |skill|
            mark = skill.installed?(OpenLanes::Skills::DESTINATION) ? "installed" : "not installed"
            "#{skill.name} (#{mark}) — #{skill.summary}"
          end
          "#{SUMMARY}, #{OpenLanes::Skills::DESTINATION} by default.\n\n#{rows.join("\n\n")}"
        end

        # Whether the caller is a group screen's command list, which dry-cli-help
        # fills through `describe_node` (and, in later releases, its
        # `node_description` helper).
        #
        # @return [Boolean]
        def self.listing?
          caller_locations(2, 3).any? { it.label.end_with?("describe_node", "node_description") }
        end
        private_class_method :listing?

        option :into,
          default: OpenLanes::Skills::DESTINATION,
          desc:    "The skill directory to copy into"
        option :overwrite,
          type:    :boolean,
          default: false,
          desc:    "Replace a skill already there, which is otherwise kept"
        dry_run_option "Copy nothing; print what would be installed, kept and replaced"

        example [
          "                           # copy each skill not yet installed",
          "--overwrite                # …and replace the ones that are, after a gem upgrade",
          "--into ~/.claude/skills    # somewhere else",
          "-n                         # show what would happen"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          quiet?(options)
          installer = OpenLanes::Skills.installer(into: options.fetch(:into, OpenLanes::Skills::DESTINATION))
          outcomes = installer.call(overwrite: options.fetch(:overwrite, false), dry_run: dry_run?(options))

          outcomes.each { |o| puts "#{o.action}\t#{o.skill.name}\t#{o.target}" }
          report(outcomes, options) unless quiet?(options)
        end

        private

        # @param outcomes [Array<OpenLanes::Skills::Installer::Outcome>]
        # @param options [Hash]
        # @return [void]
        def report(outcomes, options)
          counts = outcomes.group_by(&:action).transform_values(&:size)
          summary = %i[installed replaced kept].filter_map { |action|
            "#{counts[action]} #{action}" if counts[action]
          }.join(" · ")
          kept = counts.key?(:kept) ? "\n\nA kept skill is left as it was; --overwrite replaces it." : ""

          if dry_run?(options)
            warn("Dry run — nothing was copied.\nWould be: #{summary}#{kept}\n\nRe-run without --dry-run to apply.")
          else
            success("#{summary}#{kept}")
          end
        end
      end
    end
  end
end
