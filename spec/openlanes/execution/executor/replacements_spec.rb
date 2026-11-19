# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Replacements do
  subject(:replacements) { described_class.new }

  it "replaces nobody to begin with" do
    expect([replacements.include?("001.00", "security-reviewer"), replacements.names("001.00")]).to eq([false, []])
  end

  it "holds a replaced reviewer per plan" do
    replacements.replace("001.00", "security-reviewer")
    expect([replacements.include?("001.00", "security-reviewer"), replacements.include?("002.00", "security-reviewer")])
      .to eq([true, false])
  end

  it "lets one go" do
    replacements.replace("001.00", "security-reviewer")
    replacements.replace("001.00", "security-reviewer", on: false)
    expect(replacements.names("001.00")).to eq([])
  end

  it "ends every replacement on a plan at once" do
    replacements.replace("001.00", "security-reviewer")
    replacements.end("001.00")
    expect(replacements.include?("001.00", "security-reviewer")).to be(false)
  end
end
