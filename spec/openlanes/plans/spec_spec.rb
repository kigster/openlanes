# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Spec do
  def parse(frontmatter) = described_class.parse("---\n#{frontmatter}\n---\n# Title\n")

  describe ".parse" do
    it "defaults to the full lane with nothing overridden" do
      expect(described_class.parse("# Just a body\n")).to be_default
    end

    it "reads lane, frontend and depth" do
      expect(parse("lane: quick\nfrontend: false\ndepth: deep").to_h.slice(:lane, :frontend, :depth))
        .to eq(lane: :quick, frontend: false, depth: :deep)
    end

    it "reads per-phase overrides" do
      expect(parse("phases:\n  build: { adapter: codex, model: gpt-5-codex, effort: medium }").override_for(:build))
        .to eq("adapter" => "codex", "model" => "gpt-5-codex", "effort" => "medium")
    end

    it "reads implementation suggestions given as a list" do
      expect(parse("implementation_suggestions:\n  - Ruby with dry-cli\n  - Reuse the existing gems").suggestions)
        .to eq(["Ruby with dry-cli", "Reuse the existing gems"])
    end

    it "reads implementation suggestions given as one string" do
      expect(parse("implementation_suggestions: Rust, with clap").suggestions).to eq(["Rust, with clap"])
    end

    it "reads implementation requirements, apart from the suggestions" do
      spec = parse("implementation_requirements:\n  - The database is PG-strict\nimplementation_suggestions: Ruby")
      expect(spec.to_h.slice(:requirements, :suggestions))
        .to eq(requirements: ["The database is PG-strict"], suggestions: ["Ruby"])
    end

    it "reads how the task is finished and how to verify it" do
      spec = parse("task-completed-when:\n  - the editor opens\nhow-to-verify: bundle exec rspec")
      expect(spec.to_h.slice(:completed_when, :how_to_verify))
        .to eq(completed_when: ["the editor opens"], how_to_verify: ["bundle exec rspec"])
    end

    it "has neither completion list unless the author wrote them" do
      expect(parse("lane: plan").to_h.slice(:completed_when, :how_to_verify))
        .to eq(completed_when: [], how_to_verify: [])
    end

    it "has no requirements unless the author wrote some" do
      expect(parse("lane: plan").requirements).to eq([])
    end

    it "has no suggestions unless the author wrote some" do
      expect(parse("lane: plan").suggestions).to eq([])
    end

    it "returns no override for a phase the author did not name" do
      expect(parse("lane: plan").override_for("review")).to eq({})
    end
  end

  describe "what it ignores, and says so" do
    it "an unknown lane falls back to full" do
      expect(parse("lane: express").to_h.slice(:lane, :problems))
        .to eq(lane: :full, problems: ["lane: \"express\" is not one of full, plan, quick"])
    end

    it "a frontend that is not a boolean" do
      expect(parse("frontend: maybe").problems).to eq(["frontend: \"maybe\" is not true or false"])
    end

    it "an effort outside the scale, and keeps the rest of the phase" do
      expect(parse("phases:\n  review: { model: opus, effort: ultra }").override_for(:review)).to eq("model" => "opus")
    end

    it "an adapter nothing answers to" do
      expect(parse("phases:\n  build: { adapter: gpt }").problems.first).to start_with("phases.build.adapter:")
    end

    it "an unknown key in a phase" do
      expect(parse("phases:\n  build: { temperature: 1 }").problems).to eq(["phases.build.temperature: unknown key"])
    end

    it "phases that are not a mapping" do
      expect(parse("phases: [build]").problems.first).to start_with("phases: must be a mapping")
    end

    it "a phase that is not a mapping" do
      expect(parse("phases:\n  build: codex").problems).to eq(["phases.build: must be a mapping"])
    end

    it "suggestions that are not text, and says so" do
      expect(parse("implementation_suggestions: { language: ruby }").to_h.slice(:suggestions, :problems))
        .to eq(suggestions: [], problems: ["implementation_suggestions: must be text or a list of text"])
    end

    it "requirements that are not text, and says so" do
      expect(parse("implementation_requirements: { db: pg }").to_h.slice(:requirements, :problems))
        .to eq(requirements: [], problems: ["implementation_requirements: must be text or a list of text"])
    end

    it "a completion list that is not text, and says so" do
      expect(parse("how-to-verify: { run: it }").to_h.slice(:how_to_verify, :problems))
        .to eq(how_to_verify: [], problems: ["how-to-verify: must be text or a list of text"])
    end

    it "blank suggestions are dropped" do
      expect(parse("implementation_suggestions: ['', '  ', Ruby]").suggestions).to eq(["Ruby"])
    end

    it "frontmatter that is not YAML" do
      expect(parse("lane: [unclosed").problems.first).to start_with("spec.md frontmatter is not valid YAML")
    end
  end

  describe ".load" do
    let(:dir) { Dir.mktmpdir }

    it "reads spec.md from a plan folder" do
      File.write(File.join(dir, "spec.md"), "---\nlane: plan\n---\n# T\n")
      expect(described_class.load(dir).lane).to eq(:plan)
    end

    it "is the default when there is no spec.md" do
      expect(described_class.load(dir)).to be_default
    end
  end

  describe "depends_on" do
    it "is nil when the key is absent" do
      expect(parse("lane: plan").depends_on).to be_nil
    end

    it "is empty when the key is present and empty" do
      expect(parse("depends_on: []").depends_on).to eq([])
    end

    it "is empty when the key is present with no value" do
      expect(parse("depends_on:").depends_on).to eq([])
    end

    it "keeps quoted canonical ordinals and reports no problem" do
      spec = parse('depends_on: ["034.00"]')

      expect(spec.depends_on).to eq(["034.00"])
      expect(spec.problems).to be_empty
    end

    it "normalises a bare NNN to NNN.00, sorted and unique" do
      expect(parse('depends_on: ["050", "034", "034.00"]').depends_on).to eq(%w[034.00 050.00])
    end

    it "drops a bare number YAML read as octal, and says so" do
      spec = parse("depends_on: [034]")

      expect(spec.depends_on).to eq([])
      expect(spec.problems).to contain_exactly(a_string_including("depends_on: 28"))
    end

    it "drops a string that is not a plan number, and says so" do
      spec = parse('depends_on: ["soon", "041.00"]')

      expect(spec.depends_on).to eq(["041.00"])
      expect(spec.problems).to contain_exactly(a_string_including('"soon"'))
    end

    it "is not the default when only depends_on is set" do
      expect(parse("depends_on: []")).not_to be_default
    end
  end

  # M10: `how-to-verify:` leaves the frontmatter for a section of the body.
  describe ".migrate_how_to_verify" do
    def migrate(text) = described_class.migrate_how_to_verify(text)

    it "adds the section at the end when the spec has none, and keeps the other keys as written" do
      before = "---\nlane: quick # the short one\nhow-to-verify:\n  - bundle exec rspec\n  - just lint\n---\n# Title\n\n## Goal\n\nWork.\n"

      expect(migrate(before)).to eq(
        "---\nlane: quick # the short one\n---\n# Title\n\n## Goal\n\nWork.\n\n" \
        "## How to tell it's working?\n\n- bundle exec rspec\n- just lint\n"
      )
    end

    it "appends to the section the spec already has, before the next heading, and drops an emptied frontmatter" do
      before = "---\nhow-to-verify: run the CLI\n---\n# Title\n\n## How to tell it's working?\n\n- the page loads\n\n## Framing\n\nTwo ways.\n"

      expect(migrate(before)).to eq(
        "# Title\n\n## How to tell it's working?\n\n- the page loads\n- run the CLI\n\n## Framing\n\nTwo ways.\n"
      )
    end

    it "fills an empty section at the very end of the file" do
      expect(migrate("---\nhow-to-verify: [a]\n---\n# T\n\n## How to tell it's working?")).to eq("# T\n\n## How to tell it's working?\n\n- a\n")
    end

    it "leaves a spec without the key untouched" do
      ["# Plain\n", "---\nlane: quick\n---\n# T\n", "---\n: [\n---\n# Broken\n"].each do |text|
        expect(migrate(text)).to equal(text)
      end
    end

    # A regex took the blank line for the end of the entry and left `- b`
    # behind in the frontmatter, now under `lane:`.
    it "removes the whole list when a blank line separates its items" do
      before = "---\nhow-to-verify:\n  - a\n\n  - b\nlane: quick\n---\n# T\n"

      expect(migrate(before)).to eq("---\nlane: quick\n---\n# T\n\n## How to tell it's working?\n\n- a\n- b\n")
    end

    # A quoted key passed `meta.key?` but no regex removed it, so every
    # resync appended the checks again.
    it "removes a quoted key, and a second migration changes nothing" do
      ["\"how-to-verify\"", "'how-to-verify'"].each do |key|
        once = migrate("---\n#{key}: [a]\nlane: quick\n---\n# T\n")

        aggregate_failures do
          expect(once).to eq("---\nlane: quick\n---\n# T\n\n## How to tell it's working?\n\n- a\n")
          expect(migrate(once)).to equal(once)
        end
      end
    end

    it "leaves a flow-mapping frontmatter alone rather than cut a shared line" do
      text = "---\n{lane: quick, how-to-verify: a}\n---\n# T\n"

      expect(migrate(text)).to equal(text)
    end

    # A `|` block keeps its lines; the section must too, and read them back
    # as one check.
    it "keeps a multi-line check as one item, and reads it back whole" do
      migrated = migrate("---\nhow-to-verify: |\n  run the CLI\n  check its output\n---\n# T\n")

      aggregate_failures do
        expect(migrated).to eq("# T\n\n## How to tell it's working?\n\n- run the CLI\n  check its output\n")
        expect(described_class.parse(migrated).how_to_verify).to eq(["run the CLI\ncheck its output"])
      end
    end

    it "reads the checks from the section once the key has moved" do
      migrated = migrate("---\nhow-to-verify:\n  - bundle exec rspec\n---\n# T\n")

      expect(described_class.parse(migrated).how_to_verify).to eq(["bundle exec rspec"])
    end

    it "reads both while a spec has the key and the section, without repeating an item" do
      text = "---\nhow-to-verify: [a, b]\n---\n# T\n\n## How to tell it's working?\n\nProse is not a check.\n\n1. b\n* c\n"

      expect(described_class.parse(text).how_to_verify).to eq(%w[a b c])
    end
  end
end
