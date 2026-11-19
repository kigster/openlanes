# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::StandingOrder do
  let(:dir) { Dir.mktmpdir("standing") }
  let(:control) { File.join(dir, "control") }
  let(:handle) { instance_double(OpenLanes::Execution::Executor::Handle, control:) }

  after { FileUtils.rm_rf(dir) }

  it "keeps a HOLD for the next start" do
    File.write(control, "HOLD: a person wants a word\n")
    expect(described_class.of(handle)).to eq("HOLD: a person wants a word")
  end

  it "lets a warning about the clock go" do
    File.write(control, "WARN: 10 minutes left\n")
    expect(described_class.of(handle)).to be_nil
  end

  it "has nothing to keep without a control file" do
    expect(described_class.of(handle)).to be_nil
  end
end
