# frozen_string_literal: true

RSpec.describe OpenLanes::Evals::Scorer, :tree do
  subject(:score) { described_class.new(kase).call(folder:, run:) }

  let(:kase) do
    OpenLanes::Evals::Case.new(id: "x",
      agent: "leah-researcher",
      depth: :fast,
      description: "",
      path: "/x.yml",
      fixture: OpenLanes::Evals::Case::Fixture.new(state: :new, slug: "x", files: {}, repo: {}),
      expect:  expect_block)
  end
  let(:expect_block) { { "state" => "researched", "files_exist" => ["spec.md"] } }
  let(:spec_md) { "# X\n\n## Research\n\nFound it.\n" }
  let(:folder) do
    plans { |t| t.plan "001.00", :researched, "x", files: { "spec.md" => spec_md } }
    OpenLanes::Plans.tree(plans_root).features.first.path
  end
  let(:run) { nil }

  it "reads the state from a folder named like a plan" do
    expect(score.passed?).to be(true)
  end

  it "counts what passed" do
    expect(score.tally).to eq("2/2")
  end

  context "with a folder whose name carries no state" do
    let(:folder) do
      File.join(plans_root, "plan").tap do |dir|
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "spec.md"), spec_md)
      end
    end

    context "when the run says where it ended" do
      let(:run) { OpenLanes::Evals::Run.new(state: "researched") }

      it "takes the state from the run" do
        expect(score.passed?).to be(true)
      end
    end

    context "when nothing says where it ended" do
      it "fails the state check alone" do
        expect(score.failures.map(&:name)).to eq(["state researched"])
      end
    end
  end

  context "with a repository to compare" do
    subject(:score) { described_class.new(kase).call(folder:, repo: File.dirname(plans_root)) }

    let(:expect_block) { { "changed_paths" => ["notes.txt"] } }

    before { File.write(File.join(File.dirname(plans_root), "notes.txt"), "new\n") }

    it "scores what changed against the fixture" do
      expect(score.verdicts.map(&:detail)).to eq(["notes.txt"])
    end
  end

  context "with a case that checks nothing" do
    let(:expect_block) { {} }

    it "does not pass: it proved nothing" do
      expect(score.passed?).to be(false)
    end
  end

  it "refuses a case whose agent has gone" do
    expect { described_class.new(kase.with(agent: "nobody")) }.to raise_error(OpenLanes::Evals::Invalid, /nobody/)
  end
end
