# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::CiScaffold do
  let(:root) { Dir.mktmpdir("openlanes-scaffold") }
  let(:ruby) { OpenLanes::Setup::Stack.new(language: "ruby") }

  after { FileUtils.rm_rf(root) }

  def scaffold(provider, stack = ruby) = described_class.new(root, provider:, stack:)
  def read(path) = File.read(File.join(root, path))

  {
    github_actions: ".github/workflows/ci.yml",
    circleci:       ".circleci/config.yml",
    jenkins:        "Jenkinsfile"
  }.each do |provider, path|
    it "writes #{path} for #{provider}, running the stack's commands" do
      expect(scaffold(provider).call).to eq(described_class::Result.new(path:, written: true))
      expect(read(path)).to include("bundle exec rubocop", "bundle exec rspec")
    end
  end

  it "writes YAML that parses, for each YAML provider" do
    %i[github_actions circleci].each { scaffold(it).call }
    expect([YAML.safe_load(read(".github/workflows/ci.yml")), YAML.safe_load(read(".circleci/config.yml"))])
      .to all(be_a(Hash))
  end

  it "uses the stack's conventional pair for another language" do
    scaffold(:github_actions, OpenLanes::Setup::Stack.new(language: "node")).call
    expect(read(".github/workflows/ci.yml")).to include("npm run lint", "npm test")
  end

  it "runs just lint and just test when the justfile defines both" do
    File.write(File.join(root, "justfile"), "lint:\n  rubocop\n\ntest *args:\n  rspec {{args}}\n")
    scaffold(:github_actions).call
    expect(read(".github/workflows/ci.yml")).to include("just lint", "just test", "setup-just")
  end

  it "falls back to the stack's commands when the justfile lacks a recipe" do
    File.write(File.join(root, "justfile"), "test:\n  rspec\n")
    expect(scaffold(:jenkins).commands).to eq(["bundle exec rubocop", "bundle exec rspec"])
  end

  it "names no commands for an unknown stack" do
    expect(scaffold(:jenkins, nil).commands).to eq([])
  end

  it "leaves an existing file byte-identical" do
    FileUtils.mkdir_p(File.join(root, ".circleci"))
    File.write(File.join(root, ".circleci/config.yml"), "mine\n")
    expect(scaffold(:circleci).call.written).to be(false)
    expect(read(".circleci/config.yml")).to eq("mine\n")
  end

  it "writes nothing on a dry run" do
    expect(scaffold(:jenkins).call(dry_run: true).written).to be(false)
    expect(File.exist?(File.join(root, "Jenkinsfile"))).to be(false)
  end

  it "refuses a provider it cannot scaffold" do
    expect { scaffold(:external) }.to raise_error(ArgumentError, /external/)
  end
end
