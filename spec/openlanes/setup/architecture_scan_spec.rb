# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::ArchitectureScan do
  subject(:scan) { described_class.new(root).call }

  let(:root) { Dir.mktmpdir("openlanes-scan") }

  after { FileUtils.rm_rf(root) }

  def touch(name, text = "")
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  context "with an empty folder" do
    it { is_expected.to be_blank }
  end

  context "with a Rails application" do
    before do
      touch("Gemfile", "gem 'rails'\n")
      touch("Gemfile.lock", "GEM\n  specs:\n    rails (8.0.1)\n    pg (1.5)\n    sidekiq (7.0)\n")
      touch("justfile")
      touch(".circleci/config.yml")
      touch(".github/workflows/ci.yml")
      touch("config/credentials.yml.enc")
      touch(".envrc")
    end

    its(:layout) { is_expected.to eq(:single_application) }
    its(:languages) { is_expected.to eq(%i[ruby]) }
    its(:frameworks) { is_expected.to eq(%i[rails]) }
    its(:persistence) { is_expected.to eq(%i[postgresql]) }
    its(:background_jobs) { is_expected.to eq(%i[sidekiq]) }
    its(:task_runners) { is_expected.to eq(%i[just]) }
    its(:ci) { is_expected.to contain_exactly(:github_actions, :circleci) }
    its(:secrets) { is_expected.to eq(%i[rails_credentials]) }
    its(:env_loading) { is_expected.to eq(%i[direnv]) }
  end

  context "with a gem" do
    before { touch("acme.gemspec") }

    its(:layout) { is_expected.to eq(:library) }
    its(:deployment) { is_expected.to eq(%i[gem]) }
  end

  context "with projects below the root" do
    before do
      touch("apps/web/package.json", JSON.generate(dependencies: { react: "19" }, devDependencies: { vitest: "3" }))
      touch("services/api/requirements.txt", "fastapi==1\n")
      touch("node_modules/left-pad/package.json", "{}")
    end

    its(:layout) { is_expected.to eq(:monorepo) }
    its(:projects) { is_expected.to eq(%w[apps/web services/api]) }
    its(:languages) { is_expected.to contain_exactly(:node, :python) }
    its(:front_end) { is_expected.to eq(%i[react]) }
    its(:frameworks) { is_expected.to eq(%i[fastapi]) }
    its(:testing) { is_expected.to eq(%i[vitest]) }
  end

  context "with a workspace file" do
    before { touch("pnpm-workspace.yaml") }

    its(:layout) { is_expected.to eq(:monorepo) }
  end

  context "with a secrets file" do
    before { allow(File).to receive(:read).and_call_original }

    it "names it without opening it" do
      touch(".env", "API_KEY=not-for-reading\n")
      expect(scan.secrets).to eq(%i[dotenv])
      expect(File).not_to have_received(:read).with(File.join(root, ".env"), any_args)
    end
  end

  context "with a broken package.json" do
    before { touch("package.json", "{not json") }

    its(:languages) { is_expected.to eq(%i[node]) }
    its(:frameworks) { is_expected.to be_empty }
  end

  context "with a package.json that is not an object" do
    before { touch("package.json", "[]") }

    its(:frameworks) { is_expected.to be_empty }
  end

  context "with a folder it cannot read" do
    it "treats a file where a parent folder is expected as no projects" do
      touch("apps")
      expect(scan).to be_blank
    end
  end

  describe "its tables" do
    let(:tables) { described_class::Markers::FILES.to_a + described_class::Markers::DEPENDENCIES.to_a }

    it "name only what the closed lists hold" do
      tables.each { |attribute, values| expect(OpenLanes::Setup::Architecture.values(attribute)).to include(*values.keys) }
    end
  end
end
