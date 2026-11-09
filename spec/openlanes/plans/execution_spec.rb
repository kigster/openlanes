# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Execution do
  # Just enough of a plan folder: the files {Execution} reads.
  def folder(**files) = Struct.new(:files) { def read(name) = files[name] }.new(files.transform_keys(&:to_s))

  describe ".classify" do
    it "locks a refactor over the threshold by files" do
      expect(described_class.classify(files: [51, 100])).to eq("global-lock-required")
    end

    it "locks a refactor over the threshold by lines alone" do
      expect(described_class.classify(files: [10, 100], lines: [6_000, 10_000]))
        .to eq("global-lock-required")
    end

    it "keeps a refactor at or under the threshold concurrent" do
      expect(described_class.classify(files: [50, 100], lines: [10, 100])).to eq("concurrent")
    end

    it "honours a threshold from the settings" do
      expect(described_class.classify(files: [30, 100], threshold: 25)).to eq("global-lock-required")
    end

    it "reads an empty codebase as no share at all" do
      expect(described_class.classify(files: [3, 0])).to eq("concurrent")
    end
  end

  describe ".of" do
    it "defaults to concurrent" do
      expect(described_class.of(folder("spec.md" => "# Spec\n"))).to eq("concurrent")
    end

    it "reads plan.md before spec.md" do
      plan = folder("plan.md" => "---\nexecution: global-lock-required\n---\n",
        "spec.md" => "---\nexecution: concurrent\n---\n")
      expect(described_class.of(plan)).to eq("global-lock-required")
      expect(described_class.global_lock?(plan)).to be(true)
    end

    it "falls back to spec.md" do
      expect(described_class.of(folder("spec.md" => "---\nexecution: global-lock-required\n---\n")))
        .to eq("global-lock-required")
    end

    it "ignores a value that is not a mode, and frontmatter that is not YAML" do
      expect(described_class.of(folder("plan.md" => "---\nexecution: alone\n---\n"))).to eq("concurrent")
      expect(described_class.of(folder("plan.md" => "---\nexecution: [\n---\n"))).to eq("concurrent")
    end
  end

  describe ".refactor?" do
    it "recognises the singular key and the requirements list" do
      expect(described_class.refactor?(folder("spec.md" => "---\nimplementation_requirement: refactor\n---\n"))).to be(true)
      expect(described_class.refactor?(folder("spec.md" => "---\nimplementation_requirements: [refactor]\n---\n")))
        .to be(true)
      expect(described_class.refactor?(folder("spec.md" => "# Spec\n"))).to be(false)
    end
  end
end
