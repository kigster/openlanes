# frozen_string_literal: true

#
# bin/wiki_gen/pages.rb — the OpenLanes renderers for bin/wiki-gen.
#
# docs/wiki.yml decides which pages exist. A page there that says
# `renderer: name` is filled by `render_name(cfg)` below; everything else is
# lifted from markdown by the generic engine in bin/wiki-gen.
#
# Everything a renderer emits must be traceable: scanned out of the code, read
# from a file this repository generates (docs/architecture/, `openlanes docs`),
# or a short orientation sentence restating what the linked sources say. Facts
# OpenLanes already derives are read back from OpenLanes itself, never
# re-tabled here: the same rule as CLAUDE.md's "Nothing is written down twice".
#

# wiki-publish runs this from a temp directory; Bundler must still find our Gemfile.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __dir__)
require "bundler/setup"
require_relative "../../lib/openlanes"

module WikiGen
  # ──────────────────────────────────────────────────────────────────────────
  # Scanners: facts read out of the tree
  # ──────────────────────────────────────────────────────────────────────────

  # One file `openlanes uml self` wrote into docs/architecture/.
  Diagram = Struct.new(:const, :name, :file, :before, keyword_init: true)

  # Reads docs/architecture/, which `just update-architecture` regenerates from
  # lib/. The namespace is read from each file's H1, not from its file name,
  # because `openlanes-cli.md` holds `OpenLanes::CLI`.
  class ArchitectureScanner
    DIR = "docs/architecture"

    def initialize(repo) = @repo = repo

    # @return [Array<Diagram>] one per namespace, the root namespace first
    def diagrams
      @diagrams ||= @repo.glob("#{DIR}/openlanes*.md").filter_map do |file|
        const = Doc.new(@repo.read(file), file).title
        next unless const

        before = "#{DIR}/before/#{File.basename(file)}"
        Diagram.new(const:, name: const.delete_prefix("OpenLanes::"), file:,
                    before: @repo.exist?(before) ? before : nil)
      end
    end

    def [](name) = diagrams.find { |d| d.name == name }
    def root = self["OpenLanes"]
    def index = "#{DIR}/README.md"

    # The namespace's own doc comment: the block above `module Name` (or
    # `class Name`) in its facade file. The facade is where CLAUDE.md says a
    # namespace states its contract, so that is the one comment quoted.
    #
    # @return [Array(String, String), nil] path and comment
    def facade_doc(name)
      snake = name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      path = ["lib/openlanes/#{snake}.rb", "lib/openlanes/support/#{snake}.rb"].find { |p| @repo.exist?(p) }
      return nil unless path

      lines = @repo.lines(path)
      idx = lines.index { |l| l.match?(/^\s*(module|class)\s+#{Regexp.escape(name.split("::").last)}\b/) }
      return nil unless idx

      block = []
      i = idx - 1
      while i >= 0 && lines[i].match?(/^\s*#/)
        block.unshift(lines[i].sub(/^\s*#\s?/, "").rstrip)
        i -= 1
      end
      text = block.join("\n").strip
      text.empty? ? nil : [path, text]
    end

    # @return [Array<String>] the Ruby files behind a namespace
    def sources(name)
      snake = name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      @repo.glob("lib/openlanes/#{snake}/**/*.rb")
    end
  end

  # agents/*.md, read by their frontmatter, as `Agents::Registry` reads them.
  class AgentScanner
    def initialize(repo) = @repo = repo

    # @return [Array<Hash>] frontmatter plus `file`
    def agents
      @agents ||= @repo.glob("agents/*.md").filter_map do |file|
        front = @repo.read(file)[/\A---\n(.*?)\n---/m, 1]
        next unless front

        YAML.safe_load(front).merge("file" => file)
      end
    end

    # @return [Hash{String => Array<String>}] state key => agent names
    def handlers
      agents.each_with_object(Hash.new { |h, k| h[k] = [] }) do |a, acc|
        Array(a["handles"]).each { |s| acc[s.to_s] << a["name"] }
      end
    end
  end

  # skills/*/SKILL.md, the skills `openlanes skills install` copies.
  class SkillScanner
    def initialize(repo) = @repo = repo

    def skills
      @repo.glob("skills/*/SKILL.md").filter_map do |file|
        front = @repo.read(file)[/\A---\n(.*?)\n---/m, 1]
        front && YAML.safe_load(front).merge("file" => file)
      end
    end
  end

  # `just` recipes, with the comment lines above each as its description.
  class JustScanner
    def initialize(repo) = @repo = repo

    def recipes(file)
      lines = @repo.lines(file)
      lines.each_with_index.filter_map do |line, i|
        next if line.start_with?(" ", "\t", "#", "[")

        m = line.chomp.match(/\A(?:alias\s+([a-z][\w-]*)\s*:=\s*([a-z][\w-]*)|([a-z][\w-]*)([^:=\n]*):(?!=)(.*))\z/)
        next unless m
        next { name: m[1], args: "", deps: "", desc: "alias for `#{m[2]}`" } if m[1]

        desc = []
        j = i - 1
        while j >= 0 && lines[j].start_with?("#") && !lines[j].start_with?("#!")
          desc.unshift(lines[j].sub(/\A#\s?/, "").rstrip)
          j -= 1
        end
        { name: m[3], args: m[4].to_s.strip, deps: m[5].to_s.strip, desc: desc.join(" ") }
      end
    end
  end

  class Generator
    # ────────────────────────────────────────────────────────────────────────
    # Shared sources
    # ────────────────────────────────────────────────────────────────────────

    def architecture = @architecture ||= ArchitectureScanner.new(repo)
    def agent_scanner = @agent_scanner ||= AgentScanner.new(repo)

    # The conventions document `openlanes docs` prints, rendered in-process.
    # It is derived from STATUSES and the aasm block, so lifting from it keeps
    # the wiki's state pages exactly as current as the state machine.
    def conventions
      @conventions ||= Doc.new(OpenLanes::Presentation.documentation, "openlanes docs")
    end

    CONVENTION_SOURCES = %w[lib/openlanes/plans/status.rb lib/openlanes/plans/state_machine.rb
                            lib/openlanes/plans/ordinal.rb lib/openlanes/presentation/documentation.rb].freeze

    def conventions_label
      "the output of `openlanes docs`, generated from #{src(CONVENTION_SOURCES[0])} and " \
        "#{src(CONVENTION_SOURCES[1])}"
    end

    # `from: [{conventions: true, section: ...}]` in docs/wiki.yml.
    def lift_virtual(entry)
      return super unless entry["conventions"]

      CONVENTION_SOURCES.each { |p| cite(p) }
      lift(entry, conventions, label: conventions_label)
    end

    # The groups in docs/wiki.yml that list `namespaces:`.
    def architecture_groups
      config_pages.select { |c| c["renderer"] == "architecture_group" }
    end

    def namespace_title(name) = "OpenLanes::#{name}"

    # Called before any page is built: links to docs/architecture/*.md from
    # lifted markdown land on the namespace's wiki page.
    def register_renderer_pages
      file_pages[architecture.index] = "Namespace Map"
      architecture.diagrams.each do |d|
        file_pages[d.file] = d.name == "OpenLanes" ? "Namespace Map" : namespace_title(d.name)
      end
    end

    # A diagram file minus its H1 and its "do not edit" banner: the Mermaid.
    def mermaid(file) = Text.strip_comments(doc(cite(file)).body)

    # ────────────────────────────────────────────────────────────────────────
    # Core concepts
    # ────────────────────────────────────────────────────────────────────────

    def render_states(_cfg)
      handlers = agent_scanner.handlers
      statuses = OpenLanes::Plans::STATUSES
      cite("lib/openlanes/plans/status.rb")
      cite("lib/openlanes/plans/state_machine.rb")

      out = +"OpenLanes knows #{statuses.size} states. The folder name carries the state's emoji, so " \
             "renaming the folder is the transition. Every row below is read from `STATUSES` and the " \
             "`aasm` block at generation time.\n\n"
      rows = statuses.map do |s|
        agents = handlers[s.key.to_s].map { |n| "`#{n}`" }.join(", ")
        [s.emoji, "`#{s.key}`", s.label, s.requires.map { |r| "`#{r}`" }.join(", "),
         agents.empty? ? "_a human_" : agents, s.terminal? ? "yes" : "", Text.escape_cell(s.note)]
      end
      out << table(["", "Key", "Label", "Requires", "Moved by", "Terminal", "Meaning"], rows)
      out << "\n<sub>Read from #{src("lib/openlanes/plans/status.rb")}, " \
             "#{src("lib/openlanes/plans/state_machine.rb")} and the `handles:` frontmatter in `agents/*.md`.</sub>\n\n"

      CONVENTION_SOURCES.each { |p| cite(p) }
      out << "## Lifecycle diagrams\n\n"
      out << lift({ "preamble" => true }, conventions, label: conventions_label, level: 3) << "\n"
      out << lift({ "section" => "The states" }, conventions, label: conventions_label) << "\n"
      out << lift({ "section" => "Transitions" }, conventions, label: conventions_label)
      out
    end

    def render_agents(_cfg)
      agents = agent_scanner.agents
      agents.each { |a| cite(a["file"]) }
      rows = agents.map do |a|
        handles = Array(a["handles"]).map { |s| "`#{s}`" }.join(", ")
        ["[`#{a["name"]}`](#{blob}/#{encode(a["file"])})", handles.empty? ? "_on call_" : handles,
         a["advances_to"] ? "`#{a["advances_to"]}`" : "", a["phase"], a["model"], a["effort"],
         Text.escape_cell(a["description"])]
      end
      "## The roster\n\nRead from the frontmatter of every `agents/*.md`, which is what " \
        "`Agents::Registry` loads. An agent with no `handles:` is called by another part of the run " \
        "(arbitration, rebasing, review assistance) rather than assigned a state.\n\n" +
        table(%w[Agent Handles Advances\ to Phase Model Effort Role], rows)
    end

    def render_skills(_cfg)
      skills = SkillScanner.new(repo).skills
      skills.each { |s| cite(s["file"]) }
      rows = skills.map do |s|
        ["[`#{s["name"]}`](#{blob}/#{encode(s["file"])})", Text.first_sentence(s["description"], limit: 300)]
      end
      "Install them into `~/.agents/skills` with `openlanes skills install`. The `openlanes` skill " \
        "loads first; the others name it as a prerequisite.\n\n" + table(%w[Skill When\ it\ loads], rows)
    end

    # ────────────────────────────────────────────────────────────────────────
    # Architecture
    # ────────────────────────────────────────────────────────────────────────

    def render_namespace_map(_cfg)
      out = +"Every arrow is a dependency, labelled with the number of references one namespace makes " \
             "to the other. The diagram is regenerated from `lib/` by `just update-architecture`; " \
             "this page reads it from #{src(cite(architecture.index))}.\n\n"
      out << mermaid(architecture.index).sub(/\n- \[.*\z/m, "") << "\n\n"

      out << "## Namespaces by area\n\n"
      rows = architecture_groups.flat_map do |g|
        g["namespaces"].filter_map do |n|
          d = architecture[n] or next
          doc_text = architecture.facade_doc(n)&.last
          [link(g["title"]), link(namespace_title(n), label: "`#{d.const}`"),
           Text.first_sentence(doc_text.to_s, limit: 200)]
        end
      end
      out << table(%w[Area Namespace Summary], rows)

      if (root = architecture.root)
        out << "\n## The root namespace\n\n`OpenLanes` itself: the Zeitwerk loader and the few helpers " \
               "every namespace shares.\n\n#{mermaid(root.file)}\n"
      end
      out
    end

    # A group page: the namespaces it lists, each with its diagram on a page
    # of its own, queued to be built after this one.
    def render_architecture_group(cfg)
      names = Array(cfg["namespaces"])
      rows = names.map do |n|
        d = architecture[n]
        next ["`OpenLanes::#{n}`", "⚠️ no diagram in `docs/architecture/`; see Documentation Drift"] unless d

        [link(namespace_title(n), label: "`#{d.const}`"), Text.first_sentence(architecture.facade_doc(n)&.last.to_s)]
      end
      names.each do |n|
        d = architecture[n] or next
        later { page_namespace(d, parent: cfg["title"]) }
      end
      table(%w[Namespace Summary], rows)
    end

    def page_namespace(diagram, parent:)
      facade = architecture.facade_doc(diagram.name)
      purpose = facade && Text.first_sentence(facade.last, limit: 200).gsub('\\|', "|")
      page(namespace_title(diagram.name), parent:, purpose:) do
        out = +""
        if facade
          path, text = facade
          cite(path)
          out << "## What the namespace says about itself\n\n#{quote(text)}\n\n" \
                 "<sub>The doc comment on `#{diagram.const}` in #{src(path)}.</sub>\n\n"
        end
        out << "## Class diagram\n\nGenerated by `openlanes uml self` (`just update-architecture`) into " \
               "#{src(diagram.file)}. Dotted arrows are `uses`; classes from other namespaces are " \
               "shown where this one depends on them.\n\n#{mermaid(diagram.file)}\n\n"
        if diagram.before
          out << "<details>\n<summary>Before the 4.0 refactor</summary>\n\nFrozen in " \
                 "#{src(cite(diagram.before))}, generated once from main at a80651d.\n\n" \
                 "#{mermaid(diagram.before)}\n\n</details>\n\n"
        end
        files = architecture.sources(diagram.name)
        unless files.empty?
          out << "## Source files\n\n#{files.map { |f| "- #{src(f)}" }.join("\n")}\n"
        end
        out
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    # Development
    # ────────────────────────────────────────────────────────────────────────

    def render_just(cfg)
      scanner = JustScanner.new(repo)
      Array(cfg["files"]).map do |file|
        cite(file)
        rows = scanner.recipes(file).map do |r|
          ["`just #{r[:name]}#{" #{r[:args]}" unless r[:args].empty?}`",
           r[:deps].empty? ? "" : "`#{r[:deps]}`", Text.escape_cell(r[:desc])]
        end
        "## #{src(file)}\n\n#{table(%w[Recipe Runs\ first Description], rows)}"
      end.join("\n")
    end

    def render_circleci(cfg)
      file = cite(cfg.fetch("file"))
      ci = YAML.safe_load(repo.read(file).to_s, aliases: true) || {}
      jobs = ci.fetch("jobs", {})
      out = +"## Workflows\n\n"
      ci.fetch("workflows", {}).each do |name, wf|
        next unless wf.is_a?(Hash)

        out << "### `#{name}`\n\n```mermaid\nflowchart LR\n"
        Array(wf["jobs"]).each do |j|
          job, opts = j.is_a?(Hash) ? j.first : [j, {}]
          out << "  #{name}([#{name}]) --> #{job}\n" if Array(opts&.dig("requires")).empty?
          Array(opts&.dig("requires")).each { |req| out << "  #{req} --> #{job}\n" }
        end
        out << "```\n\n"
      end
      out << "## Jobs\n\n"
      jobs.each do |name, job|
        image = job["executor"] ? "executor `#{job["executor"]}`" : Array(job["docker"]).map { |d| "`#{d["image"]}`" }.join(", ")
        out << "### `#{name}`\n\nRuns on #{image}.\n\n"
        steps = Array(job["steps"]).map { |s| step_label(s) }
        out << steps.each_with_index.map { |s, i| "#{i + 1}. #{s}" }.join("\n") << "\n\n"
      end
      out << "<sub>Read from #{src(file)}.</sub>\n"
    end

    def step_label(step)
      return "`#{step}`" if step.is_a?(String)

      kind, body = step.first
      case body
      when Hash then body["name"] || "`#{kind}`: `#{body["command"].to_s.lines.first.to_s.strip}`"
      when String then kind == "run" ? "`#{body.lines.first.strip}`" : "`#{kind}`"
      else "`#{kind}`"
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    # Documentation drift
    # ────────────────────────────────────────────────────────────────────────

    def render_drift(_cfg)
      checks = drift_checks
      out = +"Checks the generator re-runs on every build. Each finding names the file that should " \
             "change; fix it there and the finding disappears on the next run.\n\n"
      out << (checks.empty? ? "✅ All checks pass.\n" : table(%w[Check Finding], checks))
    end

    def drift_checks
      out = []
      grouped = architecture_groups.flat_map { |g| Array(g["namespaces"]) }
      known = architecture.diagrams.map(&:name) - ["OpenLanes"]

      (known - grouped).each do |n|
        out << ["Every namespace has an area",
                "⚠️ `OpenLanes::#{n}` has a diagram in `docs/architecture/` but no group in " \
                "`docs/wiki.yml` lists it, so it has no wiki page."]
      end
      (grouped - known).each do |n|
        out << ["Every grouped namespace has a diagram",
                "❌ `docs/wiki.yml` lists `#{n}`, but `docs/architecture/` has no diagram for it. " \
                "Run `just update-architecture`, or drop it from the group."]
      end

      states = OpenLanes::Plans::STATUSES.map { |s| s.key.to_s }
      agent_scanner.agents.each do |a|
        (Array(a["handles"]).map(&:to_s) - states).each do |s|
          out << ["Agents handle real states", "❌ #{src(a["file"])} handles `#{s}`, which is not in `STATUSES`."]
        end
      end

      # Prose in docs/ that no page lifts: either the wiki is missing a page
      # or the file is dead. Generated and template files are exempt.
      exempt = %r{\Adocs/(architecture|superpowers|specs|badges|img|logos)/|\Adocs/wiki\.yml\z}
      (repo.glob("docs/**/*.md").reject { |f| f.match?(exempt) } - @used.to_a).each do |f|
        out << ["Every document in docs/ is on the wiki",
                "⚠️ #{src(f)} is lifted by no page. Add it to `docs/wiki.yml`, or delete it if it is dead."]
      end
      out
    end
  end
end
