# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Lifeline do
  describe "the supervisor's end" do
    subject(:lifeline) { described_class.open }

    after { lifeline.cut }

    it("names the read end in the child's environment") { expect(lifeline.env.fetch("OPENLANES_LIFELINE")).to match(/\A\d+\z/) }

    it("passes the read end through at the same number") do
      expect(lifeline.options.map { |from, to| [from.fileno, to.fileno] }).to eq([[Integer(lifeline.env.fetch("OPENLANES_LIFELINE"))] * 2])
    end

    it "cuts twice without complaint" do
      lifeline.cut
      expect { lifeline.cut }.not_to raise_error
    end
  end

  describe ".watch" do
    # The watcher closes the read end it was handed; this IO must not close it again.
    let(:pipe) { IO.pipe.tap { it.first.autoclose = false } }
    let(:env) { { "OPENLANES_LIFELINE" => pipe.first.fileno.to_s } }
    let(:cut) { Queue.new }

    it "calls back once the write end closes" do
      described_class.watch(env:, on_cut: -> { cut << :cut })
      pipe.last.close
      expect(cut.pop(timeout: 5)).to eq(:cut)
    end

    it "takes the variable out, so nothing this process starts inherits it" do
      described_class.watch(env:, on_cut: -> {})&.kill
      expect(env).to be_empty
    end

    it("does nothing without a supervisor") { expect(described_class.watch(env: {}, on_cut: -> {})).to be_nil }

    it("does nothing with a descriptor it cannot read") { expect(described_class.watch(env: { "OPENLANES_LIFELINE" => "x" }, on_cut: -> {})).to be_nil }
  end
end
