# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::ShutdownGrace do
  subject(:grace) { described_class.from(env, warn:) }

  let(:said) { [] }
  let(:warn) { ->(text) { said << text } }
  let(:env) { { described_class::VARIABLE => value } }
  let(:value) { nil }

  it("is what Control waits") { expect(OpenLanes::Execution::Control::GRACE).to eq(described_class.from(ENV, warn: ->(_) {})) }

  context "when unset" do
    let(:env) { {} }

    it { is_expected.to eq(60) }
  end

  context "when blank" do
    let(:value) { "  " }

    it { is_expected.to eq(described_class::DEFAULT) }
  end

  context "with a whole number of seconds" do
    let(:value) { " 15 " }

    it { is_expected.to eq(15) }
  end

  context "with zero" do
    let(:value) { "0" }

    it { is_expected.to eq(0) }
  end

  context "with something else" do
    let(:value) { "1.5m" }

    it { is_expected.to eq(described_class::DEFAULT) }
    it("says so") { grace && expect(said).to(eq(['openlanes: OPENLANES_SHUTDOWN_GRACE="1.5m" is not a whole number of seconds; using 60'])) }
  end

  context "with a negative number" do
    let(:value) { "-5" }

    it { is_expected.to eq(described_class::DEFAULT) }
  end
end
