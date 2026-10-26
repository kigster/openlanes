# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Lifecycle
    # `openlanes create` without the command: read the seed, fetch the pull
    # requests, mint the folder, and either reconstruct its spec from the
    # pull requests or scaffold and draft a new one.
    #
    # The spinner line and the warning boxes for a writer that fell through
    # draw on STDERR as the work happens. The folder, the success text and
    # the `spec.md` worth opening come back for the command to print.
    class CreateWorkflow
      include UI
      include Dry::Monads[:result]
      include Dry::Monads::Do.for(:call)

      # What a create made.
      #
      # @!attribute [r] path
      #   @return [String] the folder, where it ended up
      # @!attribute [r] message
      #   @return [String] the success text: what was made and the next step
      # @!attribute [r] spec
      #   @return [String, nil] the scaffolded `spec.md`, for a person to open;
      #     nil when nothing was scaffolded
      Created = Data.define(:path, :message, :spec)

      # @param dir [String] the `.plans` directory
      # @param root [String, nil] repository root (default: the .plans parent)
      # @param after [String, nil] mint a retroactive plan in the gap after this one
      # @param status [String, nil] open in this state instead of the default
      # @param prs [String, nil] pull request numbers or URLs, comma separated
      # @param from [String, nil] a seed markdown file, already resolved
      # @param spec [Boolean] with +prs+, write spec.md from them
      # @param draft [Boolean] without +prs+, attempt the four headings
      # @param starts [String, nil] written into spec.md's frontmatter as `starts:`
      # @param depth [String, nil] written into spec.md's frontmatter
      def initialize(dir:, root: nil, after: nil, status: nil, prs: nil, from: nil, spec: true, draft: true,
        starts: nil, depth: nil)
        @dir = dir
        @root = root
        @after = after
        @status = status
        @prs = prs
        @from = from
        @spec = spec
        @draft = draft
        @settings = { "starts" => starts, "depth" => depth }.compact
      end

      # @param words [Array<String>] the topic; empty when +from+ names it
      # @return [Dry::Monads::Result] Success({Created}), or Failure({Refusal})
      #   with 64 (usage), 65 (bad data) or 66 (no seed file)
      def call(words)
        FileUtils.mkdir_p(@dir)
        words, seed = yield resolve_seed(words)
        prs = yield fetch_prs
        path = yield mint(words, prs)

        Success(created(path, prs, seed))
      end

      private

      # @param message [String]
      # @param status [Integer]
      # @return [Dry::Monads::Result::Failure]
      def refusal(message, status) = Failure(Refusal.new(message:, status:))

      # `--from FILE` trades the words argument for a markdown file: the
      # frontmatter's `title:` names the folder, and the body travels on to
      # {Brief} as the author's own opening statement. Words and a file are
      # two answers to one question — the folder's name — so holding both is
      # refused rather than silently ranked.
      #
      # @param words [Array<String>]
      # @return [Dry::Monads::Result] Success([slug words, seed body or nil])
      def resolve_seed(words)
        return Success([words, nil]) unless @from

        unless words.empty?
          return refusal("--from names the topic by its frontmatter title;\ndrop the words, or drop --from", 64)
        end
        if @prs
          return refusal("--prs reconstructs spec.md from the pull requests, so a seed file\n" \
                         "would be ignored; use one or the other",
            64)
        end
        return refusal("Could not read the seed file:\n#{@from} does not exist", 66) unless File.file?(@from)

        parse_seed(File.read(@from, encoding: "UTF-8"))
      end

      # Frontmatter that will not parse used to be reported as a missing
      # title, which sends the author looking for a `title:` line that is
      # sitting right there. Say which of the two actually went wrong.
      #
      # @param content [String]
      # @return [Dry::Monads::Result] Success([title words, body])
      def parse_seed(content)
        meta, body = Frontmatter.split(content)
        title = meta["title"].to_s
        if title.strip.empty?
          return refusal("The seed file needs a frontmatter title, e.g.\n---\ntitle: Tax Rule DSL\n---", 65)
        end

        Success([title.split, body.strip])
      rescue Psych::Exception => e
        refusal("The seed file's frontmatter is not valid YAML:\n#{e.message}", 65)
      end

      # A retroactive plan documents work that landed *somewhere* in the
      # sequence, and only its author knows where. Guessing would put the
      # number — the one thing that never changes — in the wrong place.
      #
      # @return [Dry::Monads::Result] Success(Array<Hash>) or Success(nil) without +prs+
      def fetch_prs
        return Success(nil) unless @prs

        unless @after
          return refusal("--prs documents work that already shipped;\n" \
                         "name the plan it landed after with --after, e.g. --after 018",
            64)
        end

        Success(Vcs.github.pull_requests(Vcs::GitHub.parse_refs(@prs)))
      rescue OpenLanes::Error => e
        refusal("Could not read the pull requests:\n#{e.message}", 65)
      end

      # @param words [Array<String>]
      # @param prs [Array<Hash>, nil]
      # @return [Dry::Monads::Result] Success(path)
      def mint(words, prs)
        Lifecycle.create(dir: @dir, words:, after: @after, status: @status, prs:)
                 .alt_map { |message| Refusal.new(message: "Could not create the plan:\n#{message}", status: 65) }
      end

      # A plan with recorded pull requests already has its facts — hand it to
      # the writer that reconstructs a specification from a diff. One without
      # them does not exist yet, and reconstructing is not the job; {#brief} is.
      #
      # @param path [String]
      # @param prs [Array<Hash>, nil]
      # @param seed [String, nil]
      # @return [Created]
      def created(path, prs, seed)
        from_prs = prs && !prs.empty?
        spec = nil
        if from_prs
          path = synthesize(path) if @spec
        else
          spec = brief(path, seed)
        end

        feature = Plans::Feature.parse(path)
        Created.new(path:,
          spec:,
          message: "Created #{File.basename(path)}\n\n" \
                   "#{feature.status.emoji} #{feature.status.label} — #{feature.status.note}\n" \
                   "#{next_step(path, feature, from_prs:)}")
      end

      # Hand the folder to the writer that already knows how to write a
      # retroactive specification, then let `resync dirs` decide what the
      # folder has become — ⏪ is only true while there is no `spec.md`.
      #
      # @param path [String]
      # @return [String] the folder's path, which the resync may have renamed
      def synthesize(path)
        agent = OpenLanes::Agents.registry.find(OpenLanes::RETROACTIVE_WRITER) or return path

        feature = Plans::Feature.parse(path)
        ok, note = on_agent_row("Writing spec.md from #{UI.paint(File.basename(path).to_s, :yellow)}",
          agent: agent.name,
          plan:  feature.ordinal.to_s) do |line|
          Execution.executor(root: root_of(path)).call(agent, Plans.subject(feature), &line)
        end
        unless ok
          error("The folder was created, but spec.md was not written:\n#{note}\n\n" \
                "The pull requests are recorded. Run `openlanes run` to retry.")
        end

        settle(path)
      end

      # A folder with no pull requests to reconstruct from is a feature that
      # does not exist yet. {Brief} writes the four headings a human still has
      # to answer and makes a best-effort pass at them from what the project
      # already has on disk. The folder's state never moves: ⚪ New only ever
      # claimed that a specification exists, not that it is complete.
      #
      # @param path [String]
      # @param seed [String, nil] the seed body from the `--from` file
      # @return [String, nil] the scaffolded spec.md; nil for a retroactive folder
      def brief(path, seed)
        feature = Plans::Feature.parse(path)
        return if feature.status.key == :retroactive

        brief = Lifecycle.brief(path:, title: feature.title, root: root_of(path), seed:)
        brief.write_scaffold!
        draft(brief, feature, seed) if @draft
        # After the draft, so a drafting agent that rewrites the file cannot
        # drop `--starts` and `--depth`.
        brief.stamp!(@settings)
        brief.spec_path
      end

      # @param brief [OpenLanes::Lifecycle::Brief]
      # @param feature [OpenLanes::Plans::Feature]
      # @param seed [String, nil]
      # @return [void]
      def draft(brief, feature, seed)
        # Painted the way Runner::Task#label paints a roster agent, so the
        # half-agent reads as one of them on the terminal.
        label = "#{UI.paint(Brief::AGENT_NAME, :yellow, :bold)} drafting spec.md from #{seed}"
        ok, note = on_agent_row(label, agent: Brief::AGENT_NAME, plan: feature.ordinal.to_s) { brief.attempt! }
        return if ok

        error("spec.md was scaffolded, but the drafting attempt did not finish:\n#{note}\n\n" \
              "The four headings are there, empty. Fill them in by hand, or hand off to #{Agents::Names::RESEARCHER}.")
      end

      # @param path [String] a plan folder
      # @return [String] the repository root the agents work in
      def root_of(path) = @root || File.dirname(path, 2)

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

      # @param path [String]
      # @return [String] where the folder ended up
      def settle(path)
        change = Lifecycle.resync_dirs(tree: Plans.tree(File.dirname(path)))
                          .call(commit: true)
                          .find { |c| c.source == path }
        change ? change.target : path
      end

      # @param path [String]
      # @param feature [OpenLanes::Plans::Feature]
      # @param from_prs [Boolean]
      # @return [String]
      def next_step(path, feature, from_prs:)
        spec = File.join(File.basename(path), "spec.md")
        return "Next: write #{spec}" unless feature.status.key == :new && File.file?(File.join(path, "spec.md"))
        if from_prs
          return "Next: read #{spec} — it was written from the pull requests, so check it against what actually shipped"
        end

        "Next: fill in the four headings in #{spec}, then hand off to #{Agents::Names::RESEARCHER}"
      end
    end
  end
end
