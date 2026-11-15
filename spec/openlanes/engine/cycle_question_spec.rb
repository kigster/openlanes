# frozen_string_literal: true

# Plans that wait on each other are held for good, so a person is asked
# which of them goes first.
RSpec.describe OpenLanes::Engine::CycleQuestion, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  def subject_for(ordinal) = tree.reload.find(OpenLanes::Plans::Ordinal.parse(ordinal))

  def asked(ordinal) = described_class.questions(subject_for(ordinal), tree.dependencies)

  def declared(ordinal) = OpenLanes::Plans::Spec.for(subject_for(ordinal)).depends_on

  context "with three plans on a cycle and one waiting on it" do
    before do
      plans do |t|
        t.plan "001.00", :planned, "a", files: { "spec.md" => needs("002.00", "009.00") }
        t.plan "002.00", :planned, "b", files: { "spec.md" => needs("003.00") }
        t.plan "003.00", :planned, "c", files: { "spec.md" => needs("001.00") }
        t.plan "004.00", :planned, "d", files: { "spec.md" => needs("001.00") }
        t.plan "009.00", :approved, "done"
      end
    end

    it "asks once, on the lowest plan, and recommends freeing it" do
      shown = asked("001.00")
      aggregate_failures do
        expect(shown.size).to eq(1)
        expect(shown.first).to include(id: "001.00/C1",
          kind: "cycle",
          owner: "technical",
          agent: nil,
          held: false,
          heading: described_class::HEADING)
        expect(shown.first[:body]).to include("`001.00 → 002.00 → 003.00 → 001.00`", "001.00, 002.00, 003.00", "`.plans/`")
        expect(shown.first[:options]).to eq([{ letter: "a", recommended: true,
                                               label: "Remove 001.00's dependency on 002.00, so 001.00 runs next",
                                               answer: "a) Remove 001.00's dependency on 002.00, so 001.00 runs next" }])
        expect(%w[002.00 003.00 004.00 009.00].flat_map { asked(it) }).to be_empty
      end
    end

    it "takes the option's letter: the lowest plan loses its entries on the cycle and keeps the rest" do
      fix = described_class.answer!(tree, "001.00", "a) Remove 001.00's dependency on 002.00, so 001.00 runs next")
      aggregate_failures do
        expect(fix.to_s).to eq("001.00 no longer depends on 002.00")
        expect(declared("001.00")).to eq(["009.00"])
        expect(declared("002.00")).to eq(["003.00"])
        expect(tree.dependencies.cycles).to be_empty
        expect(tree.dependencies.reason("001.00")).to be_nil
        expect(asked("001.00")).to be_empty
      end
    end

    it "takes a plan number in words: that plan runs next" do
      fix = described_class.answer!(tree, "001.00", "3")
      aggregate_failures do
        expect(fix).to have_attributes(plan: "003.00", removed: ["001.00"])
        expect(declared("003.00")).to eq([])
        expect(File.read(File.join(subject_for("003.00").feature.path, "spec.md"))).to include("depends_on: [none]")
        expect(declared("001.00")).to eq(["002.00", "009.00"])
        expect(tree.dependencies.reason("003.00")).to be_nil
      end
    end

    it "refuses an answer that names no plan on the cycle, and writes nothing" do
      aggregate_failures do
        %w[maybe 004.00 099].each do |said|
          expect { described_class.answer!(tree, "001.00", said) }
            .to raise_error(described_class::Invalid, /C1 takes a\) or one of 001.00, 002.00, 003.00, not "#{said}"/)
        end
        expect(tree.reload.dependencies.cycles).to eq([%w[001.00 002.00 003.00 001.00]])
      end
    end

    it "has nothing to answer on a plan the question does not hang on" do
      expect(described_class.answer!(tree, "002.00", "a")).to be_nil
      expect(described_class.answer!(tree, "004.00", "a")).to be_nil
    end
  end

  context "with a plan that waits on itself" do
    before { plans { |t| t.plan "005.00", :planned, "self", files: { "spec.md" => needs("005.00") } } }

    it "asks, and the answer drops the entry" do
      expect(asked("005.00").first[:options].first[:label]).to eq("Remove 005.00's dependency on 005.00, so 005.00 runs next")
      described_class.answer!(tree, "005.00", "a")
      expect(tree.dependencies.cycles).to be_empty
    end
  end

  context "with two cycles that share a plan" do
    before do
      plans do |t|
        t.plan "001.00", :planned, "a", files: { "spec.md" => needs("002.00") }
        t.plan "002.00", :planned, "b", files: { "spec.md" => needs("001.00", "003.00") }
        t.plan "003.00", :planned, "c", files: { "spec.md" => needs("002.00") }
      end
    end

    it "asks again, on the lowest plan of what is left" do
      described_class.answer!(tree, "001.00", "a")
      aggregate_failures do
        expect(asked("001.00")).to be_empty
        expect(asked("002.00").first).to include(id: "002.00/C1")
        expect(asked("002.00").first[:body]).to include("`002.00 → 003.00 → 002.00`")
      end
    end
  end

  context "with a depends_on the rewrite cannot be trusted with" do
    before do
      plans do |t|
        t.plan "001.00", :planned, "a", files: { "spec.md" => "---\ndepends_on:\n- \"002.00\"\n# note\n- \"009.00\"\n---\n#{spec_body}" }
        t.plan "002.00", :planned, "b", files: { "spec.md" => needs("001.00") }
      end
    end

    it "leaves the spec as written and says to edit it by hand" do
      path = File.join(subject_for("001.00").feature.path, "spec.md")
      before = File.read(path)
      expect { described_class.answer!(tree, "001.00", "a") }.to raise_error(described_class::Invalid, /edit it by hand/)
      expect(File.read(path)).to eq(before)
    end
  end
end
