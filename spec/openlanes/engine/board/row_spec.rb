# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Board::Row do
  describe ".remember" do
    subject { described_class.remember(history, text) }

    let(:history) { ["reading spec.md"] }

    context "with a new status" do
      let(:text) { "editing plan.md" }

      it { is_expected.to eq(["editing plan.md", "reading spec.md"]) }
    end

    # An agent restating its activity is not news.
    context "with the newest status repeated" do
      let(:text) { "reading spec.md" }

      it { is_expected.to eq(["reading spec.md"]) }
    end

    context "with a blank status" do
      let(:text) { "  " }

      it { is_expected.to eq(["reading spec.md"]) }
    end

    context "with no status and no history" do
      let(:history) { [] }
      let(:text) { nil }

      it { is_expected.to eq([]) }
    end

    context "with a full history" do
      let(:history) { (1..described_class::HISTORY).map(&:to_s) }
      let(:text) { "new" }

      it { is_expected.to have_attributes(size: described_class::HISTORY, first: "new") }
    end
  end
end
