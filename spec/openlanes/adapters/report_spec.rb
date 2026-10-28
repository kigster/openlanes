# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Report do
  subject(:table) { strip_ansi(described_class.new(availabilities).render) }

  let(:at) { Time.utc(2026, 10, 27, 9) }
  let(:availabilities) do
    [OpenLanes::Adapters::Availability.up("claude", OpenLanes::Adapters::Claude::MODELS, at),
     OpenLanes::Adapters::Availability.down("pi", "no model provider signed in", at),
     OpenLanes::Adapters::Availability.unchecked(OpenLanes::Adapters.for("codex"))]
  end
  let(:row) { ->(name) { table.lines.find { it.include?(" #{name} ") } } }

  it { is_expected.to include("Adapter", "Available", "Can", "Models") }
  it { expect(row.call("claude")).to include("yes", "compacts, resumes, refuses denied tools", OpenLanes::Adapters::Claude::MODELS.size.to_s) }
  it { expect(row.call("pi")).to include("no model provider signed in", "—", " 0 ") }
  it { expect(row.call("codex")).to include("not checked yet") }

  context "with colour" do
    subject(:table) { described_class.new(availabilities).render }

    before { allow(OpenLanes::UI).to receive(:color?).and_return(true) }

    it { is_expected.to include("\e[") }
  end
end
