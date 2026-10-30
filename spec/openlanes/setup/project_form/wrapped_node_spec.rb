# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::ProjectForm::WrappedNode do
  subject(:wrapped) { described_class.new(node, 30) }

  let(:node) { OpenLanes::Setup::ProjectForm.definition.step(:desired_codebase_quality) }

  it "wraps the question" do
    expect(wrapped.question.lines.map { it.chomp.length }).to all(be <= 30)
  end

  it "wraps each label, indenting its later lines past the pointer" do
    label = wrapped.option_labels.fetch("high").lines
    expect([label.map { it.chomp.length }, label[1]]).to match([all(be <= 30), start_with("    ")])
  end

  it "answers everything else as the step" do
    expect(wrapped.id).to eq(:desired_codebase_quality)
  end

  it "leaves a step with no labels alone" do
    plain = described_class.new(OpenLanes::Setup::ProjectForm.definition.step(:project), 30)
    expect(plain.option_labels).to be_nil.or be_empty
  end
end
