# frozen_string_literal: true

# What the ladder (E2) does to a running agent through its handle.
RSpec.describe OpenLanes::Execution::Executor::Handle do
  subject(:handle) { described_class.new }

  let(:control) { File.join(Dir.mktmpdir, "control") }
  let(:ticks) { { t: 0.0 } }
  let(:clock) { OpenLanes::Execution::Clock.new(seconds: 100, control:, on_expire: -> {}, now: -> { ticks[:t] }) }
  let(:restarts) { [] }

  before do
    File.write(control, "")
    handle.on_restart = ->(fields) { restarts << fields }
  end

  it "says and holds nothing before there is a clock" do
    expect([handle.say!("ESTIMATE: x"), handle.hold!(180)]).to eq([false, false])
  end

  context "with a clock running" do
    before { handle.clock = clock }

    it "says a line through the clock" do
      expect([handle.say!("ESTIMATE: x"), File.read(control).strip]).to eq([true, "ESTIMATE: x"])
    end

    it "holds the clock at a floor, and records the new deadline for a restarted engine" do
      aggregate_failures do
        expect(handle.hold!(180)).to be(true)
        expect(handle.remaining).to eq(180)
        expect(restarts.map(&:keys)).to eq([[:deadline]])
      end
    end

    it "records nothing when the clock did not move" do
      handle.hold!(50)
      expect(restarts).to eq([])
    end
  end
end
