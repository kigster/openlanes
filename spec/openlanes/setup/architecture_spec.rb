# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::Architecture do
  subject(:architecture) { described_class.new(ci: %w[github_actions circleci], layout: "monorepo", projects: %w[web api]) }

  its(:ci) { is_expected.to eq(%i[github_actions circleci]) }
  its(:layout) { is_expected.to eq(:monorepo) }
  its(:blank?) { is_expected.to be(false) }
  its(:to_file) { is_expected.to eq("layout" => "monorepo", "projects" => %w[web api], "ci" => %w[github_actions circleci]) }

  it "reads back what it writes" do
    expect(described_class.new(architecture.to_file)).to eq(architecture)
  end

  it "refuses a value outside its list" do
    expect { described_class.new(ci: %w[travis]) }.to raise_error(Dry::Struct::Error)
  end

  it "refuses a key it does not know" do
    expect { described_class.new(cii: %w[circleci]) }.to raise_error(Dry::Struct::Error)
  end

  it "is blank when nothing is known" do
    expect(described_class.new).to be_blank
  end

  describe ".asked_at" do
    it "asks more the more detail is wanted" do
      expect(described_class::DETAILS.map { described_class.asked_at(it).size }).to eq([10, 15, 21])
    end
  end

  describe ".recommended" do
    it "recommends the house tools" do
      expect(described_class.recommended([])).to include(task_runners: %i[just], secrets: %i[sopsy], env_loading: %i[direnv])
    end

    it "lets a Rails application keep its own encrypted secrets" do
      expect(described_class.recommended(%i[rails])).to include(secrets: %i[rails_credentials])
    end
  end

  describe "an attribute" do
    subject(:attribute) { described_class::ATTRIBUTES.find { it.name == :ci } }

    its(:label) { is_expected.to eq("CI") }
    its(:prompt_now) { is_expected.to end_with("today?") }
    its(:prompt_wanted) { is_expected.to end_with("use?") }
  end

  it "words a question its own way when the general one reads badly" do
    layout = described_class::ATTRIBUTES.first
    expect([layout.label, layout.prompt_now]).to match(["Layout", include("monorepo")])
  end
end
