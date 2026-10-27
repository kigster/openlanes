# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::AgentProcess::Registry do
  # A class of its own, so the real AgentProcess and its exit hook are left alone.
  let(:registry) { Class.new.extend(described_class) }

  let(:agent) { instance_double(OpenLanes::Execution::AgentProcess, kill: nil) }

  before do
    allow(registry).to receive(:at_exit).and_return(proc {})
    registry.track(agent)
  end

  it("lists what it tracks") { expect(registry.live).to eq([agent]) }
  it("installs one exit hook however many it tracks") { registry.track(agent) && expect(registry).to(have_received(:at_exit).once) }
  it("forgets an agent") { registry.forget(agent) && expect(registry.live).to(be_empty) }

  describe "#exiting" do
    context "with an engine that never said it can take its agents back" do
      before { registry.exiting(quit: false) }

      it("stops them") { expect(agent).to have_received(:kill).with("TERM") }
    end

    context "with an engine that can take them back" do
      before { registry.reattachable! }

      it "leaves them to a crash or a TERM" do
        registry.exiting(quit: false)
        expect(agent).not_to have_received(:kill)
      end

      it "stops them on a deliberate quit" do
        registry.exiting(quit: true)
        expect(agent).to have_received(:kill).with("TERM")
      end

      it "stops them again once reset" do
        registry.reset!
        registry.exiting(quit: false)
        expect(agent).to have_received(:kill).with("TERM")
      end
    end
  end
end
