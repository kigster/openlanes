# frozen_string_literal: true

RSpec.describe OpenLanes::Lifecycle::Linker, :tree do
  subject(:linker) { described_class.new(tree:, registry:, executor:, plans: only) }

  let(:registry) { OpenLanes::Agents.registry }
  let(:only) { nil }
  let(:calls) { [] }
  let(:ok) { true }
  let(:writes) { 'depends_on: ["034.00"]' }
  let(:executor) do
    lambda do |agent, subject, root:|
      calls << [agent.name, subject.feature.ordinal.to_s, root]
      spec = File.join(subject.feature.path, "spec.md")
      File.write(spec, File.read(spec).sub(/^depends_on:.*\n/, "").sub("---\n", "---\n#{writes}\n")) if ok && writes
      Struct.new(:ok, :note).new(ok, ok ? "done" : "agent died")
    end
  end
  let(:tree) { OpenLanes::Plans.tree(plans_root) }

  before do
    plans do |t|
      t.plan "050.00", :ready_for_linking, "keyless", files: { "spec.md" => spec, "plan.md" => "" }
      t.plan "051.00", :planned, "empty-list", files: { "spec.md" => spec("depends_on: []") }
      t.plan "052.00", :ready_for_planning, "none", files: { "spec.md" => spec("depends_on: [none]") }
      t.plan "053.00", :planned, "linked", files: { "spec.md" => spec('depends_on: ["034.00"]') }
      t.plan "054.00", :approved, "shipped", files: { "spec.md" => spec }
    end
  end

  def spec(key = nil) = "---\nlane: full\n#{key && "#{key}\n"}---\n# Spec\n"

  def ordinals(list) = list.map { it.feature.ordinal.to_s }

  describe "#candidates" do
    it "takes a missing key and [], and leaves [none], a list and ✅ alone" do
      expect(ordinals(linker.candidates)).to eq(%w[050.00 051.00])
    end

    context "with --plans" do
      let(:only) { %w[051] }

      it("narrows to those plans") { expect(ordinals(linker.candidates)).to eq(%w[051.00]) }
    end
  end

  describe "#call" do
    it "invokes the 🔗 agent once per candidate, serially, and reports what it linked" do
      result = linker.call

      expect(calls.map(&:first).uniq).to eq(["ewoki-linker"])
      expect(calls.map { it[1] }).to eq(%w[050.00 051.00])
      expect(ordinals(result.linked)).to eq(%w[050.00 051.00])
      expect(result).to be_ok
    end

    it "moves a plan it linked at 🔗 on to 📋, and leaves every other folder's name alone" do
      linker.call
      tree.reload

      expect(tree.find("050.00").status.key).to eq(:ready_for_planning)
      expect(tree.find("051.00").status.key).to eq(:planned)
    end

    context "when the links close a cycle" do
      let(:writes) { 'depends_on: ["053.00"]' }

      before do
        spec = File.join(tree.find("053.00").feature.path, "spec.md")
        File.write(spec, File.read(spec).sub('"034.00"', '"050.00"'))
      end

      it "reports the cycle, and is not ok" do
        result = linker.call

        expect(result.cycles).to include(%w[050.00 053.00 050.00])
        expect(result).not_to be_ok
      end
    end

    it "invokes nothing on a dry run" do
      result = linker.call(dry_run: true)

      expect(calls).to be_empty
      expect(ordinals(result.unchanged)).to eq(%w[050.00 051.00])
    end

    context "when the agent writes nothing" do
      let(:writes) { nil }

      it("reports the plan unchanged") { expect(ordinals(linker.call.unchanged)).to eq(%w[050.00 051.00]) }
    end

    context "when the agent fails" do
      let(:ok) { false }

      it "reports each failure with its note, and is not ok" do
        result = linker.call

        expect(result.failed.map { |s, note| [s.feature.ordinal.to_s, note] })
          .to eq([["050.00", "agent died"], ["051.00", "agent died"]])
        expect(result).not_to be_ok
      end
    end
  end

  context "when no agent handles 🔗" do
    let(:registry) { OpenLanes::Agents.registry.without("ewoki-linker") }

    it("raises, naming the state") { expect { linker.call }.to raise_error(OpenLanes::Error, /Ready for Linking/) }
  end

  it "is reached through the Lifecycle facade" do
    expect(OpenLanes::Lifecycle.link(tree:, registry:, executor:)).to be_a(described_class)
  end
end
