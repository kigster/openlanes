# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::ProjectForm::Preselection do
  subject(:preselection) { described_class.new(scan:, file:, config: { project: "Acme" }) }

  let(:architecture) { OpenLanes::Setup::Architecture }
  let(:scan) { architecture.new(ci: %w[circleci], layout: "library", projects: %w[web api]) }
  let(:file) { OpenLanes::Setup::ArchitectureDecisions.none }

  it "shows the scan for NOW" do
    expect(preselection.for(:current_ci, {})).to eq(%w[circleci])
  end

  it "shows one word for a single answer" do
    expect(preselection.for(:current_layout, {})).to eq("library")
  end

  it "joins folders for a text answer" do
    expect(preselection.for(:current_projects, {})).to eq("web, api")
  end

  it "shows nothing for what nothing said" do
    expect(preselection.for(:current_caching, {})).to be_nil
  end

  it "answers the other questions from the file" do
    expect([preselection.for(:project, {}), preselection.for(:starts, {})]).to eq(["Acme", nil])
  end

  it "answers a step named like an attribute that is none" do
    expect(preselection.for(:target_nonsense, {})).to be_nil
  end

  describe "WANTED" do
    it "shows what NOW was answered" do
      expect(preselection.for(:target_ci, { current_ci: %w[jenkins] })).to eq(%w[jenkins])
    end

    it "falls back to the scan" do
      expect(preselection.for(:target_ci, {})).to eq(%w[circleci])
    end

    it "recommends when nothing else says" do
      expect(preselection.for(:target_secrets, {})).to eq(%w[sopsy])
    end

    it "keeps a Rails application on its own secrets" do
      expect(preselection.for(:target_secrets, { current_frameworks: %w[rails] })).to eq(%w[rails_credentials])
    end

    context "with the current file's answer" do
      let(:file) do
        OpenLanes::Setup::ArchitectureDecisions.new(detail: nil, migration: nil, current: architecture.new, target: architecture.new(ci: %w[github_actions]))
      end

      it "prefers it to NOW" do
        expect(preselection.for(:target_ci, { current_ci: %w[jenkins] })).to eq(%w[github_actions])
      end
    end

    context "with a description" do
      before { preselection.understand({ target_ci: %w[buildkite], merge_by: "auto" }) }

      it "prefers the description to everything" do
        expect(preselection.for(:target_ci, { current_ci: %w[jenkins] })).to eq(%w[buildkite])
      end

      it "preselects the other answers it settled" do
        expect(preselection.for(:merge_by, {})).to eq("auto")
      end
    end
  end
end
