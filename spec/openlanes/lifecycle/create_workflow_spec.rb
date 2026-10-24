# frozen_string_literal: true

# `openlanes create` as a workflow: no dry-cli command, no exit, nothing
# shelled out (`draft: false`).
RSpec.describe OpenLanes::Lifecycle::CreateWorkflow, :tree do
  def create(*words, **)
    described_class.new(dir: plans_root, draft: false, **).call(words)
  end

  def seed_file(content)
    File.join(Dir.mktmpdir("seed"), "notes.md").tap { |f| File.write(f, content) }
  end

  describe "a topic given as words" do
    subject(:created) { create("tax", "rule", "dsl").value! }

    it "mints the folder and answers where it is" do
      expect(created.path).to eq(File.join(plans_root, "000.00━━⚪━━❯tax-rule-dsl"))
    end

    it "answers the scaffolded spec.md for a person to open" do
      expect(File.read(created.spec)).to include("# Tax Rule DSL")
    end

    it "words the success text with the state and the next step" do
      expect(created.message).to include("Created 000.00━━⚪━━❯tax-rule-dsl", "fill in the four headings")
    end
  end

  it "stamps lane and depth into spec.md's frontmatter" do
    spec = create("split", "migration", starts: "building", depth: "fast").value!.spec

    expect(OpenLanes::Plans::Spec.parse(File.read(spec)).to_h.slice(:starts, :depth)).to eq(starts: :building, depth: :fast)
  end

  describe "a seed file" do
    it "names the folder from its frontmatter title" do
      seeded = seed_file("---\ntitle: Tax Rule DSL\n---\nRules should read like the statute.\n")

      expect(File.basename(create(from: seeded).value!.path)).to eq("000.00━━⚪━━❯tax-rule-dsl")
    end

    {
      "with words beside it"      => [%w[tax rule], "---\ntitle: T\n---\n", 64, "drop the words, or drop --from"],
      "with no frontmatter title" => [[], "Just prose.", 65, "frontmatter title"],
      "with frontmatter not YAML" => [[], "---\ntitle: [unclosed\n---\nbody\n", 65, "not valid YAML"]
    }.each do |label, (words, content, status, phrase)|
      it "refuses a seed #{label} with #{status}" do
        failure = create(*words, from: seed_file(content)).failure

        expect([failure.status, failure.message]).to match([status, a_string_including(phrase)])
      end
    end

    it "refuses a seed file that is not there with 66, minting nothing" do
      expect(create(from: "/no/such/notes.md").failure.status).to eq(66)
      expect(Dir.children(plans_root)).to be_empty
    end

    it "refuses a seed file beside --prs with 64" do
      expect(create(from: seed_file("---\ntitle: T\n---\n"), prs: "12").failure.status).to eq(64)
    end
  end

  it "refuses --prs without --after with 64, naming the flag" do
    failure = create("verify", prs: "12").failure

    expect([failure.status, failure.message]).to match([64, a_string_including("--after")])
  end

  it "refuses pull requests GitHub cannot read with 65" do
    github = instance_double(OpenLanes::Vcs::GitHub)
    allow(OpenLanes::Vcs::GitHub).to receive(:new).and_return(github)
    allow(github).to receive(:pull_requests).and_raise(OpenLanes::Error, "gone")
    plans { |t| t.plan("002.00", :new, "anchor", files: { "spec.md" => spec_body }) }

    expect(create("verify", after: "002", prs: "12").failure.status).to eq(65)
  end

  it "refuses a topic that slugs to nothing with 65" do
    failure = create("---").failure

    expect([failure.status, failure.message]).to match([65, a_string_including("Could not create the plan")])
  end
end
