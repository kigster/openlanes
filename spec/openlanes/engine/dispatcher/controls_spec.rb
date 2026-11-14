# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Controls, :tree do
  subject(:controls) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  it "answers false or nil for a key nothing runs under" do
    expect([controls.kill("009.00/x"), controls.extend("009.00/x", 60), controls.requeue("009.00/x"),
            controls.compact("009.00/x")]).to eq([nil, false, false, nil])
  end

  it "says it cannot prefer a model when the executor cannot take one" do
    executor = Object.new
    allow(runner).to receive(:executor).and_return(executor)
    expect(controls.prefer_model("001.00", coder.name, "opus")).to be(false)
  end

  it "forgets the cached model label when a model is preferred" do
    executor = Struct.new(:chosen) { def prefer_model(*args) = self.chosen = args }.new
    allow(runner).to receive(:executor).and_return(executor)
    desk.models[["001.00", coder.name]] = "old"
    expect([controls.prefer_model("001.00", coder.name, "opus"), desk.models]).to eq([true, {}])
  end

  it "passes a concurrency change to the runner" do
    allow(runner).to receive(:jobs=)
    controls.concurrency = 3
    expect(runner).to have_received(:jobs=).with(3)
  end
end
