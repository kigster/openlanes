# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module CLI
    # `openlanes create <words…>` — backs /spec-create.
    class Create < Base
      desc "Create the next numbered plan folder"

      argument :words,
        type: :array,
        required: false,
        default: [],
        desc:
          "The topic, two to five words; becomes the folder slug. Omit when --from names it"

      option :from,
        aliases: ["-f"],
        desc:
          "Seed from a markdown file: its frontmatter `title:` names the folder, and its body fills the spec."
      option :after,
        aliases: ["-a"],
        desc:
          "Create a retroactive plan in the gap after this plan, e.g. 002"
      option :status,
        aliases: ["-s"],
        desc:    "Open in a state other than the default"
      option :prs,
        aliases: ["--pr"],
        desc:
          "Document work that already shipped: pull request numbers or URLs, comma separated. Requires --after"
      option :spec,
        type: :boolean,
        default: true,
        desc:
          "With --prs, write spec.md from what the pull requests did. --no-spec records them and stops, which is fast and offline"
      option :draft,
        type: :boolean,
        default: true,
        desc:
          "For a new feature (no --prs), attempt spec.md's four headings from project context via `claude`. --no-draft leaves them bare"
      option :lane,
        aliases: ["-l"],
        values:  Plans::Spec::LANES.map(&:to_s),
        desc:
          "Route the plan: full (research, spec, plan, build), plan (skip research and rewriting), " \
          "quick (one agent does a short mechanical task). Written into spec.md's frontmatter"
      option :depth,
        values: Plans::Spec::DEPTHS.map(&:to_s),
        desc:   "How hard every phase should think: fast, medium or deep. Written into spec.md's frontmatter"
      option :open,
        type: :boolean,
        default: true,
        desc:
          "Open the new spec.md in the system editor when done (macOS `open`). --no-open leaves it for you to open"

      # noinspection RubyMismatchedArgumentType
      example [
        "tax rule dsl                        # 003.00-⚪️ → tax-rule-dsl, spec.md scaffolded and drafted",
        "tax rule dsl --no-draft --no-open   # scaffold only, nothing shelled out, nothing opened",
        "--after 002 schedule k1             # 002.01-🕰️-schedule-k1 (documented after the fact)",
        "--after 018 --prs 12,15 verify      # …and write spec.md from what those PRs did",
        "--after 018 --pr https://…/pull/12 verify # verify the pull request by number or URL",
        "--status ready billing sync         # opens at ⭐️ instead of ⚪️",
        "--from notes/tax-dsl.md             # title and opening prose from the file's frontmatter and body",
        "--lane quick split big migration    # r2d2-mechanic does it and opens the PR; no research, spec or plan"
      ]

      # @param words [Array<String>]
      # @param options [Hash]
      # @return [void]
      def call(words:, **options)
        dir = options.fetch(:dir, OpenLanes::PLANS_DIR)
        FileUtils.mkdir_p(dir)

        words, seed = resolve_seed(words, options)
        prs = fetch_prs(options)
        result =
          Lifecycle.create(dir:,
            words:,
            after:  options[:after],
            status: options[:status],
            prs:)

        result.either(
          ->(path) { created(path, prs, options, seed:) },
          ->(message) { refuse("Could not create the plan:\n#{message}", 65) }
        )
      end

      private

      # `--from FILE` trades the words argument for a markdown file: the
      # frontmatter's `title:` names the folder, and the body travels on to
      # {Brief} as the author's own opening statement. Words and a file are
      # two answers to one question — the folder's name — so holding both is
      # refused rather than silently ranked.
      #
      # @param words [Array<String>]
      # @param options [Hash]
      # @return [Array(Array<String>, String, nil)] the slug words, and the
      #   seed body when a file supplied them
      def resolve_seed(words, options)
        file = typed_path(options[:from])
        return words, nil unless file

        unless words.empty?
          refuse(
            "--from names the topic by its frontmatter title;\n" \
            "drop the words, or drop --from",
            64
          )
        end
        if options[:prs]
          refuse(
            "--prs reconstructs spec.md from the pull requests, so a seed file\n" \
            "would be ignored; use one or the other",
            64
          )
        end
        unless File.file?(file)
          refuse("Could not read the seed file:\n#{file} does not exist", 66)
        end

        title, body = parse_seed(File.read(file, encoding: "UTF-8"))
        if title.to_s.strip.empty?
          refuse(
            "The seed file needs a frontmatter title, e.g.\n" \
            "---\ntitle: Tax Rule DSL\n---",
            65
          )
        end

        [title.split, body]
      end

      # Frontmatter that will not parse used to be reported as a missing
      # title, which sends the author looking for a `title:` line that is
      # sitting right there. Say which of the two actually went wrong.
      #
      # @param content [String]
      # @return [Array(String, String)] title and body
      def parse_seed(content)
        meta, body = Frontmatter.split(content)
        [meta["title"].to_s, body.strip]
      rescue Psych::Exception => e
        refuse(
          "The seed file's frontmatter is not valid YAML:\n#{e.message}",
          65
        )
      end

      # A retroactive plan documents work that landed *somewhere* in the
      # sequence, and only its author knows where. Guessing would put the
      # number — the one thing that never changes — in the wrong place.
      #
      # @param options [Hash]
      # @return [Array<Hash>, nil]
      def fetch_prs(options)
        return nil unless options[:prs]

        unless options[:after]
          refuse(
            "--prs documents work that already shipped;\n" \
            "name the plan it landed after with --after, e.g. --after 018",
            64
          )
        end

        Vcs.github.pull_requests(Vcs::GitHub.parse_refs(options[:prs]))
      rescue OpenLanes::Error => e
        refuse("Could not read the pull requests:\n#{e.message}", 65)
      end

      # A plan with recorded pull requests already has its facts — hand it to
      # the writer that reconstructs a specification from a diff. One without
      # them does not exist yet, and reconstructing is not the job; {#brief} is.
      #
      # @param path [String]
      # @param prs [Array<Hash>, nil]
      # @param options [Hash]
      # @return [void]
      def created(path, prs, options, seed: nil)
        from_prs = prs && !prs.empty?
        path =
          if from_prs
            synthesize(path, options) if options.fetch(:spec, true)
          else
            brief(path, options, seed:)
          end || path
        puts path
        return if quiet?(options)

        feature = Plans::Feature.parse(path)
        success(
          "Created #{File.basename(path)}\n\n" \
          "#{feature.status.emoji} #{feature.status.label} — #{feature.status.note}\n" \
          "#{next_step(path, feature, from_prs:)}"
        )
      end

      # Hand the folder to the writer that already knows how to write a
      # retroactive specification, then let `resync dirs` decide what the
      # folder has become — 🕰️ is only true while there is no `spec.md`.
      #
      # @param path [String]
      # @param options [Hash]
      # @return [String] the folder's path, which the resync may have renamed
      def synthesize(path, options)
        agent = OpenLanes::Agents.registry.find(OpenLanes::RETROACTIVE_WRITER) or
          return path
        root = options[:root] || File.dirname(path, 2)

        feature = Plans::Feature.parse(path)
        ok, note = on_agent_row("Writing spec.md from #{UI.paint(File.basename(path).to_s, :yellow)}",
          agent: agent.name,
          plan:  feature.ordinal.to_s) do |line|
          Execution.executor(root:).call(agent, Plans.subject(feature), &line)
        end
        warn_about(note) unless ok

        settle(path)
      end

      # A folder with no pull requests to reconstruct from is a feature that
      # does not exist yet. {Brief} writes the four headings a human still has
      # to answer, makes a best-effort pass at them from what the project
      # already has on disk, and — unless told not to — opens the result for
      # a human to finish. The folder's state never moves: ⚪️ New only ever
      # claimed that a specification exists, not that it is complete.
      #
      # @param path [String] the path to the folder
      # @param seed [String, nil] the seed body from the `--from` file
      # @param options [Hash] the options hash
      # @return [String] +path+, unchanged
      def brief(path, options, seed: nil)
        feature = Plans::Feature.parse(path)
        return path if feature.status.key == :retroactive

        root = options[:root] || File.dirname(path, 2)
        brief = Lifecycle.brief(path:, title: feature.title, root:, seed:)
        brief.write_scaffold!

        if options.fetch(:draft, true)
          # Painted the way Runner::Task#label paints a roster agent, so the
          # half-agent reads as one of them on the terminal.
          label =
            "#{UI.paint(Lifecycle::Brief::AGENT_NAME, :yellow, :bold)} drafting spec.md from #{seed}"
          ok, note = on_agent_row(label, agent: Lifecycle::Brief::AGENT_NAME, plan: feature.ordinal.to_s) { brief.attempt! }
          warn_about_draft(note) unless ok
        end

        brief.stamp!({ "lane" => options[:lane], "depth" => options[:depth] }.compact)
        open_spec(brief.spec_path) if options.fetch(:open, true)
        path
      end

      # One agent writing spec.md, drawn as a spinner line.
      #
      # @param label [String] the spinner line's text
      # @param agent [String]
      # @param plan [String]
      # @yieldparam line [OpenLanes::UI::Line]
      # @return [Object] the block's value
      def on_agent_row(label, agent:, plan:, &block)
        Execution.on_interrupt do
          UI.concurrently([plan],
            label,
            jobs:   1,
            label:  ->(_) { label },
            fields: ->(_) { { plan:, agent: } }) { |_, line| block.call(line) }.first
        end
      end

      # @param spec_path [String]
      # @return [void]
      def open_spec(spec_path)
        return unless macos?

        system("open", spec_path, out: File::NULL, err: File::NULL)
      end

      # `open` is a macOS command; anywhere else the viewer step is skipped
      # rather than failed. A named seam so a spec can assert the viewer was
      # asked for without inheriting the platform CI happens to run on.
      #
      # @return [Boolean]
      def macos? = RbConfig::CONFIG["host_os"].to_s.match?(/darwin/)

      # @param path [String]
      # @return [String] where the folder ended up
      def settle(path)
        tree = Plans.tree(File.dirname(path))
        change =
          OpenLanes::Lifecycle::Resync::Dirs
          .new(tree:)
          .call(commit: true)
          .find { |c| c.source == path }
        change ? change.target : path
      end

      # @param note [String]
      # @return [void]
      def warn_about(note)
        error(
          "The folder was created, but spec.md was not written:\n#{note}\n\n" \
          "The pull requests are recorded. Run `openlanes run` to retry."
        )
      end

      # @param note [String]
      # @return [void]
      def warn_about_draft(note)
        error(
          "spec.md was scaffolded, but the drafting attempt did not finish:\n#{note}\n\n" \
          "The four headings are there, empty. Fill them in by hand, or hand off to leah-researcher."
        )
      end

      # @param path [String]
      # @param feature [OpenLanes::Plans::Feature]
      # @return [String]
      def next_step(path, feature, from_prs:)
        spec = File.join(File.basename(path), "spec.md")
        unless feature.status.key == :new &&
               File.file?(File.join(path, "spec.md"))
          return "Next: write #{spec}"
        end
        if from_prs
          return (
            "Next: read #{spec} — it was written from the pull requests, so check it against what actually shipped"
          )
        end

        "Next: fill in the four headings in #{spec}, then hand off to leah-researcher"
      end
    end
  end
end
