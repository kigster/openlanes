# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Child do
  context "with a fake spawner" do
    it "starts nothing and keeps the pid the spawner handed back" do
      spawner = OpenLanes::Spawner::Fake.new(pids: [4242])
      child = described_class.spawn(%w[claude -p hello], chdir: "/tmp", env: { "A" => "1" }, spawner:)
      described_class.forget(child)
      call = spawner.calls.first
      aggregate_failures do
        expect(child.pid).to eq(4242)
        expect(call.argv).to eq(%w[claude -p hello])
        expect(call.env).to include("A" => "1")
        expect(call.options).to include(chdir: "/tmp", pgroup: true, unsetenv_others: true)
      end
    end
  end
end
