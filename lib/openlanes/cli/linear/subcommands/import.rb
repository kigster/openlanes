# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes linear …`
    module Linear
      # `linear import` — the plans, as Linear issues under one of your projects.
      class Import < Team
        desc "Create Linear issues from the plans: one per folder, one child per work unit"

        option :project,
          aliases: ["-p", "--project-url", "--project-id"],
          desc:    "The project to file everything under: its URL, its name, or its id"
        dry_run_option "Send nothing to Linear; print what would be created and updated"
        option :format,
          default: "text",
          values:  %w[text json],
          desc:    "json emits the exact arguments the Linear MCP tools take"
        option :since,
          aliases: ["-s"],
          desc:    "Skip plans numbered below this, e.g. 010.00"
        option :status,
          desc: "Only plans in these states: a comma-separated list of status keys"
        option :update_unchanged,
          type:    :boolean,
          default: false,
          desc:    "Update everything, whether the plan has changed or not"

        example [
          "TAX -p 'US Tax Law: Self Contained Ruby Gem'   # list what would be created",
          "TAX -p https://linear.app/acme/project/…       # a URL works too",
          "TAX -p 'Ruby Gem' -n                           # preview, sending nothing",
          "TAX -p 'Ruby Gem' --format json                # hand it to the MCP transport instead",
          "TAX -p 'Ruby Gem' --since 010.00               # only the recent plans",
          "TAX -p 'Ruby Gem' --status building,in_review"
        ]

        # @param team [String]
        # @param options [Hash]
        # @return [void]
        def call(team:, **options)
          tree = tree_for(options).everything
          require_project!(options)
          import = build(tree, team, resolve_project(team, tree, options), options)

          return $stdout.puts(import.to_json) if options[:format] == "json"

          if import.pending.empty?
            success("Linear is already in step with #{tree.dir}.") unless quiet?(options)
            return
          end

          preview(import, options)
        rescue OpenLanes::Error => e
          refuse(e.message, 69)
        end

        private

        # Looking the project up costs a token, and the whole point of
        # `--format json` is to work without one. A name needs no lookup — the
        # MCP server resolves a project by name itself — so only a URL or an
        # id, which do not carry a name, force the network.
        #
        # @return [Hash] `{"id", "name", "url"}`
        def resolve_project(team, tree, options)
          reference = options[:project].to_s
          looks_up = reference.match?(%r{\Ahttps?://}) || reference.match?(/\A[0-9a-f-]{32,}\z/)
          return { "id" => nil, "name" => reference, "url" => nil } if !looks_up && offline?

          _api, survey = survey_for(team, tree)
          survey.project(reference)
        end

        # @return [Boolean]
        def offline? = OpenLanes::Linear::API.token_from_env.nil?

        # @param options [Hash]
        # @return [void]
        def require_project!(options)
          return if options[:project]

          raise OpenLanes::Error,
            "which project? Pass -p with a project's URL, name or id.\n\n" \
            "This never creates one: a team's project list is something you curated, and " \
            "every plan is filed under one you named.\n\n  " \
            "openlanes linear projects <TEAM>   lists them"
        end

        # @return [OpenLanes::Linear::Import]
        def build(tree, team, project, options)
          OpenLanes::Linear::Import.new(tree:,
            team: OpenLanes::Linear.key!(team),
            project:,
            since: options[:since],
            statuses: statuses(options),
            update_unchanged: options.fetch(:update_unchanged, false))
        end

        # @param options [Hash]
        # @return [Array<Symbol>, nil]
        def statuses(options)
          return nil unless options[:status]

          options[:status].to_s.split(",").map { |word|
            OpenLanes::Plans.status(word.strip)&.key ||
              raise(OpenLanes::Error, "no such state: #{word.strip}")
          }
        end

        # @param import [OpenLanes::Linear::Import]
        # @param options [Hash]
        # @return [void]
        def preview(import, options)
          import.pending.each { |action| puts row(action) }
          return if quiet?(options)

          import.pending.each { |action| say(line(action)) }
          report_unplaced(import)
          what = "Linear change#{"s" unless import.pending.size == 1}"
          return dry_run_footer(import.pending.size, what) if dry_run?(options)

          # There is no push of its own here yet: the MCP transport is what
          # applies these. Saying so beats implying something was sent.
          warn("#{import.pending.size} #{what} pending — nothing was sent.\n" \
               "This command does not write to Linear itself: pipe --format json to the Linear MCP tools.")
        end

        # @param action [OpenLanes::Linear::Action]
        # @return [String]
        def row(action)
          [action.op, action.kind, action.ordinal, action.unit || "-",
           action.identifier || "-", action.title].join("\t")
        end

        # @param action [OpenLanes::Linear::Action]
        # @return [String]
        def line(action)
          verb = paint(action.op.to_s.ljust(6), action.op == :create ? :green : :yellow)
          indent = action.child? ? "    " : ""
          "#{verb} #{indent}#{action.title}  #{paint("(#{action.reason})", :bright_black)}"
        end

        # @param import [OpenLanes::Linear::Import]
        # @return [void]
        def report_unplaced(import)
          return if import.unplaced.empty?

          listed = import.unplaced.map { |status, ordinals|
            "  #{status} — #{ordinals.join(", ")}\n#{wrapped(OpenLanes::Linear.reason_unplaced(status))}"
          }
          warn("Not imported, because nothing here knows where they belong:\n\n" \
               "#{listed.join("\n\n")}\n\n" \
               "Decide where they go on your board and add it to Linear::PLACEMENTS.")
        end

        # A box re-wraps a line that overruns it, and the wrapped remainder
        # comes back at column zero — which reads as a new entry rather than
        # the continuation of one. Wrapping it here keeps the indent.
        #
        # @param text [String]
        # @param width [Integer] narrower than the narrowest box
        # @return [String]
        def wrapped(text, width: 58)
          text.split.each_with_object([+""]) { |word, lines|
            lines << +"" if lines.last.length + word.length + 1 > width
            lines.last << " " unless lines.last.empty?
            lines.last << word
          }.map { |line| "    #{line}" }.join("\n")
        end
      end
    end
  end
end
