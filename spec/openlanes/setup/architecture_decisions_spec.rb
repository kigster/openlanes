# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::ArchitectureDecisions do
  let(:path) { "/tmp/.openlanes.yml" }
  let(:architecture) { OpenLanes::Setup::Architecture }

  def decisions(current: {}, target: {}, detail: nil, migration: nil)
    described_class.new(detail:, migration:, current: architecture.new(current), target: architecture.new(target))
  end

  describe ".none" do
    subject { described_class.none }

    it { is_expected.to be_empty }
    its(:to_file) { is_expected.to be_nil }
  end

  describe ".parse" do
    it "is nil with no section" do
      expect(described_class.parse(nil, path:)).to be_nil
    end

    it "reads back what #to_file writes" do
      held = decisions(current: { ci: %w[circleci] }, target: { ci: %w[github_actions] }, detail: :high, migration: :port)
      expect(described_class.parse(held.to_file, path:)).to eq(held)
    end

    {
      "a list"               => [%w[nope], /must be a mapping/],
      "an unknown key"       => [{ "verison" => 1 }, /unknown key verison/],
      "an unknown detail"    => [{ "detail" => "huge" }, /detail: huge is not one of/],
      "an unknown value"     => [{ "target" => { "ci" => ["travis"] } }, /architecture_decisions/],
      "an unknown member"    => [{ "current" => { "cii" => ["circleci"] } }, /architecture_decisions/],
      "an unknown migration" => [{ "migration" => "wait" }, /migration: wait is not one of/]
    }.each do |name, (value, message)|
      it "refuses #{name}" do
        expect { described_class.parse(value, path:) }.to raise_error(OpenLanes::Error, message)
      end
    end
  end

  describe ".from_legacy" do
    subject(:held) do
      described_class.from_legacy(legacy_ci: { provider: :circleci, config: ".circleci/config.yml" },
        stack: { language: "Ruby", frameworks: %w[rails remix], persistence: "postgresql", domain: "shops" })
    end

    it "keeps what the closed lists can hold, on both sides" do
      expect([held.current, held.target]).to all(have_attributes(ci: %i[circleci],
        languages: %i[ruby],
        frameworks: %i[rails],
        persistence: %i[postgresql]))
    end

    it "takes a file with neither" do
      expect(described_class.from_legacy(legacy_ci: nil, stack: nil)).to be_empty
    end
  end

  describe "#stack" do
    it "names the language beside node's asset tooling" do
      expect(decisions(target: { languages: %w[ruby node] }).stack.language).to eq("ruby")
    end

    it "names node alone" do
      expect(decisions(target: { languages: %w[node] }).stack.language).to eq("node")
    end

    it "guesses nothing between two languages" do
      expect(decisions(target: { languages: %w[ruby go] }).stack).to be_empty
    end

    it "leaves the non-answers out" do
      stack = decisions(target: { languages: %w[other], frameworks: %w[rails other], persistence: %w[none] }).stack
      expect(stack.to_h).to eq(frameworks: %w[rails])
    end

    it "records both ends of a port" do
      stack = decisions(current: { languages: %w[python], frameworks: %w[django] },
        target: { languages: %w[ruby], frameworks: %w[rails] },
        migration: :port).stack
      expect([stack.from, stack.to]).to eq(%w[python/django ruby/rails])
    end
  end

  describe "#to_file" do
    subject do
      decisions(current: { ci: %w[circleci] }, target: { ci: %w[circleci] }, detail: :low).to_file
    end

    it { is_expected.to eq("version" => 1, "detail" => "low", "current" => { "ci" => %w[circleci] }, "target" => { "ci" => %w[circleci] }) }
  end
end
