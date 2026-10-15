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

  describe "#unacked" do
    let(:fields) do
      { key: "001.00/luke-backend", at: Time.now, ordinal: "001.00", file: "plan.md", agent: "luke-backend",
        role: "builder", round: 1, rounds: 2, model: "opus", up: 0, down: 0, state: :running }
    end

    it "defaults to 0, so a row built without a mailbox reading draws no warning" do
      expect(described_class.new(**fields).unacked).to eq(0)
    end

    it "carries a count it is given" do
      expect(described_class.new(**fields, unacked: 2).unacked).to eq(2)
    end
  end

  describe ".unacked_in", :tree do
    let!(:dir) do
      path = nil
      plans { |t| path = t.plan("001.00", :new, "mail", files: { "spec.md" => "# Spec" }) }
      path
    end

    it "is 0 for a plan nobody has written to" do
      expect(described_class.unacked_in(dir)).to eq(0)
    end

    it "counts the messages nobody has acked" do
      mailbox = OpenLanes::Plans.mailbox(dir)
      first = mailbox.append(from: "luke-backend", to: "rey-frontend", body: "B1 landed")
      mailbox.append(from: "rey-frontend", to: "luke-backend", body: "Which field?")
      mailbox.ack(first.number, by: "rey-frontend")

      expect(described_class.unacked_in(dir)).to eq(1)
    end
  end
end
