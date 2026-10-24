# frozen_string_literal: true

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
      option :starts,
        values: Plans::Spec::STARTS.map(&:to_s),
        desc:
          "Where the plan starts: research (the whole spine), planning (skip research), " \
          "building (one agent, a short mechanical task). Written into spec.md as starts:"
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
        "tax rule dsl                        # 003.00━━⚪━━❯tax-rule-dsl, spec.md scaffolded and drafted",
        "tax rule dsl --no-draft --no-open   # scaffold only, nothing shelled out, nothing opened",
        "--after 002 schedule k1             # 002.01━━⏪━━❯schedule-k1 (documented after the fact)",
        "--after 018 --prs 12,15 verify      # …and write spec.md from what those PRs did",
        "--after 018 --pr https://…/pull/12 verify # verify the pull request by number or URL",
        "--status ready billing sync         # opens at ⭐ instead of ⚪",
        "--from notes/tax-dsl.md             # title and opening prose from the file's frontmatter and body",
        "--starts building split big migration    # r2d2-mechanic does it and opens the PR; no research, spec or plan"
      ]

      # @param words [Array<String>]
      # @param options [Hash]
      # @return [void]
      def call(words:, **options)
        workflow = Lifecycle.create_plan(dir: options.fetch(:dir, OpenLanes::PLANS_DIR),
          **options.slice(:root, :after, :status, :prs, :spec, :draft, :starts, :depth),
          from: typed_path(options[:from]))
        created = unwrap(workflow.call(words))

        open_spec(created.spec) if created.spec && options.fetch(:open, true)
        puts created.path
        success(created.message) unless quiet?(options)
      end

      private

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
    end
  end
end
