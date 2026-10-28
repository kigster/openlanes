# frozen_string_literal: true

# U3: R4's question, put once per project on the first
# review-passed pull request while the key is missing.
RSpec.describe OpenLanes::Engine::QualityQuestion, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:root) { File.dirname(plans_root) }
  let(:config) { File.join(root, OpenLanes::Config::FILE) }

  before do
    plans do |t|
      t.plan "001.00", :in_review, "first"
      t.plan "002.00", :in_review, "second"
    end
  end

  def dir(ordinal) = tree.reload.find(OpenLanes::Plans::Ordinal.parse(ordinal)).feature.path

  def subject_for(ordinal) = tree.reload.find(OpenLanes::Plans::Ordinal.parse(ordinal))

  def state(ordinal) = OpenLanes::Plans::PlanState.for(dir(ordinal))

  describe ".ask!" do
    it "asks on the first plan and on no other" do
      expect(described_class.ask!(dir("001.00"))).to be(true)
      expect(described_class.ask!(dir("002.00"))).to be(false)
      expect(state("002.00").quality_ask).to be_nil
    end

    it "keeps the first moment when the same plan asks again" do
      described_class.ask!(dir("001.00"), at: Time.utc(2026, 10, 19, 9))
      expect(described_class.ask!(dir("001.00"), at: Time.utc(2026, 10, 19, 10))).to be(true)
      expect(Time.iso8601(state("001.00").quality_ask["asked_at"])).to eq(Time.utc(2026, 10, 19, 9))
    end
  end

  describe ".questions" do
    it "shows the question once, on the plan that asked, with R4's three options" do
      described_class.ask!(dir("001.00"))
      shown = described_class.questions(subject_for("001.00"), state("001.00"))
      expect(shown.size).to eq(1)
      expect(shown.first).to include(id: "001.00/Q1", kind: "quality", heading: described_class::HEADING)
      expect(shown.first[:options].map { it[:letter] }).to eq(%w[a b c])
      expect(shown.first[:options].first[:recommended]).to be(true)
      expect(described_class.questions(subject_for("002.00"), state("002.00"))).to be_empty
    end
  end

  describe ".answer!" do
    before { described_class.ask!(dir("001.00")) }

    it "writes the key, keeps the file's comments, and closes the question" do
      File.write(config, "# kept\njobs: 2")
      expect(described_class.answer!(dir("001.00"), "c", by: "someone", root:)).to eq(:mvp)
      expect(File.read(config)).to eq("# kept\njobs: 2\ndesired_codebase_quality: mvp\n")
      expect(OpenLanes::Config.load(root).desired_codebase_quality).to eq(:mvp)
      expect(described_class.questions(subject_for("001.00"), state("001.00"))).to be_empty
      expect(described_class.open_in(plans_root)).to be_nil
    end

    it "takes standard, the middle level, at high's max_rejections" do
      expect(described_class.answer!(dir("001.00"), "b", by: "someone", root:)).to eq(:standard)
      expect(OpenLanes::Config.load(root)).to have_attributes(desired_codebase_quality: :standard, max_rejections: 2)
    end

    it "writes the answer and all three options into decisions.md beside the plans" do
      described_class.answer!(dir("001.00"), "b", by: "dana", root:, at: Time.utc(2026, 10, 20))
      text = File.read(File.join(plans_root, described_class::DECISIONS))
      aggregate_failures do
        expect(text).to start_with("# Decisions\n\n## desired_codebase_quality: standard\n")
        expect(text).to include("Decided by dana on 2026-10-20", "a) high: ", "c) mvp: ", "SOLID")
        expect(text).to match(/^b\) standard: .*\*\*\(chosen\)\*\*$/)
        expect(text).not_to match(/^a\) .*chosen/)
      end
    end

    it "appends to a decisions.md already there" do
      File.write(File.join(plans_root, described_class::DECISIONS), "# Decisions\n\n## Earlier\n")
      described_class.answer!(dir("001.00"), "a", by: "dana", root:)
      expect(File.read(File.join(plans_root, described_class::DECISIONS)))
        .to start_with("# Decisions\n\n## Earlier\n\n## desired_codebase_quality: high\n")
    end

    it "settles from the terminal: the key, decisions.md, and the question left open on the page" do
      expect(described_class.settle!(root:, plans_dir: plans_root, quality: :mvp, by: "openlanes run")).to eq(:mvp)
      aggregate_failures do
        expect(File.read(config)).to eq("desired_codebase_quality: mvp\n")
        expect(File.read(File.join(plans_root, described_class::DECISIONS))).to include("Decided by openlanes run")
        expect(described_class.open_in(plans_root)).to be_nil
      end
    end

    it "creates the file when there is none" do
      described_class.answer!(dir("001.00"), "A", by: "someone", root:)
      expect(File.read(config)).to eq("desired_codebase_quality: high\n")
    end

    it "leaves a key someone wrote meanwhile alone" do
      File.write(config, "desired_codebase_quality: high\n")
      described_class.answer!(dir("001.00"), "b", by: "someone", root:)
      expect(File.read(config)).to eq("desired_codebase_quality: high\n")
    end

    it "answers nothing twice" do
      described_class.answer!(dir("001.00"), "a", by: "someone", root:)
      expect(described_class.answer!(dir("001.00"), "b", by: "someone", root:)).to be_nil
    end

    it "refuses a letter that is not an option" do
      expect { described_class.answer!(dir("001.00"), "d", by: "someone", root:) }.to raise_error(ArgumentError, /d is not one of a\), b\), c\)/)
    end
  end
end
