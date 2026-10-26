# frozen_string_literal: true

RSpec.describe OpenLanes::Live::RunState do
  subject(:state) { described_class.new }

  it "holds and releases questions and cars, once each" do
    state.hold_question("001.00/B1")
    state.hold_question("001.00/B1")
    state.hold_car("001.00/backend-coder")
    state.hold_car("001.00/backend-coder", held: false)
    expect([state.question_held?("001.00/B1"), state.car_held?("001.00/backend-coder")]).to eq([true, false])
  end

  it "counts each real change, and no repeat of one" do
    state.hold_question("001.00/B1")
    state.hold_question("001.00/B1")
    state.choose_model("001.00/backend-coder", "claude-haiku-5-5")
    state.choose_model("001.00/backend-coder", "claude-haiku-5-5")
    state.hold_car("001.00/backend-coder", held: false)
    expect(state.seq).to eq(2)
  end

  describe "its written record" do
    subject(:copy) { described_class.new.restore(state.to_h) }

    before { state.hold_car("001.00/frontend-coder") }

    it "is taken back whole, sequence number included" do
      expect([copy.seq, copy.car_held?("001.00/frontend-coder"), copy.models]).to eq([1, true, {}])
    end
  end

  it "restores a garbled record as empty" do
    expect(described_class.new.restore("models" => "x").to_h).to eq("seq" => 0, "held_questions" => [], "held_cars" => [], "models" => {})
  end

  context "with a model chosen" do
    before { state.choose_model("001.00/backend-coder", "claude-haiku-5-5") }

    it "remembers it" do
      expect(state.model_for("001.00/backend-coder")).to eq("claude-haiku-5-5")
    end

    it "forgets it when told nil" do
      state.choose_model("001.00/backend-coder", nil)
      expect(state.model_for("001.00/backend-coder")).to be_nil
    end
  end

  context "with a concurrency set from the copilot" do
    before { state.concurrency = 2 }

    it "remembers it, and moves seq once" do
      state.concurrency = 2
      expect([state.concurrency, state.seq]).to eq([2, 1])
    end

    it "survives a restore" do
      expect(described_class.new.restore(state.to_h).concurrency).to eq(2)
    end

    it "restores a limit under 1 as unset" do
      expect(described_class.new.restore("concurrency" => 0).concurrency).to be_nil
    end
  end
end
