# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::ProjectForm::Answers do
  subject(:decisions) { described_class.new(answers:, scan:, file:, wanted_ci:).decisions }

  let(:architecture) { OpenLanes::Setup::Architecture }
  let(:answers) { {} }
  let(:scan) { architecture.new(ci: %w[circleci], languages: %w[ruby]) }
  let(:file) { OpenLanes::Setup::ArchitectureDecisions.none }
  let(:wanted_ci) { nil }

  context "with no answers, as under -y" do
    it "records the scan on both sides, and no recommendation" do
      expect([decisions.current, decisions.target]).to all(eq(scan))
    end

    its(:detail) { is_expected.to be_nil }
    its(:migration) { is_expected.to be_nil }
  end

  context "with --ci" do
    let(:wanted_ci) { :jenkins }

    it "says what is wanted, not what is there" do
      expect([decisions.current.ci, decisions.target.ci]).to eq([%i[circleci], %i[jenkins]])
    end
  end

  context "when what is there is also what is wanted" do
    let(:answers) { { detail: "low", current_ci: %w[github_actions], keep_current: true, target_ci: %w[jenkins] } }

    its(:detail) { is_expected.to eq(:low) }

    it "makes target the answered current" do
      expect([decisions.current.ci, decisions.target.ci]).to eq([%i[github_actions], %i[github_actions]])
    end
  end

  context "when something else is wanted" do
    let(:answers) { { keep_current: false, target_languages: %w[go], migration: "port", target_projects: "web, api" } }

    its(:migration) { is_expected.to eq(:port) }

    it "keeps every other attribute as it is" do
      expect(decisions.target).to have_attributes(languages: %i[go], ci: %i[circleci], projects: %w[web api])
    end
  end

  context "with a question this detail does not ask, settled by the description" do
    let(:answers) { { understanding: { target_persistence: %w[postgresql] } } }

    it "still records it" do
      expect(decisions.target.persistence).to eq(%i[postgresql])
    end
  end

  context "with an empty answer" do
    let(:answers) { { current_ci: [] } }

    it "keeps what the scan found" do
      expect(decisions.current.ci).to eq(%i[circleci])
    end
  end

  context "with a file" do
    let(:file) do
      OpenLanes::Setup::ArchitectureDecisions.new(detail: :high,
        migration: :fresh,
        current: architecture.new(caching: %w[redis]),
        target: architecture.new(ci: %w[github_actions]))
    end

    its(:detail) { is_expected.to eq(:high) }
    its(:migration) { is_expected.to eq(:fresh) }

    it "keeps its answers beside the scan's" do
      expect(decisions.current).to have_attributes(caching: %i[redis], ci: %i[circleci])
      expect(decisions.target.ci).to eq(%i[github_actions])
    end
  end

  describe ".paths" do
    it "reads commas and spaces" do
      expect(described_class.paths("web, api  docs")).to eq(%w[web api docs])
    end

    it "takes nothing" do
      expect(described_class.paths(nil)).to eq([])
    end
  end
end
