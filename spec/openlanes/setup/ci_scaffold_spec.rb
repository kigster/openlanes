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

  it "names no commands for an unknown stack, and writes no file that would check nothing" do
    expect([scaffold(:jenkins, nil).commands, scaffold(:jenkins, nil).call]).to eq(
      [[], described_class::Result.new(path: "Jenkinsfile", written: false, skipped: described_class::NOTHING_TO_RUN)]
    )
    expect(File.exist?(File.join(root, "Jenkinsfile"))).to be(false)
  end

  {
    "Ruby"       => "bundle exec rspec",
    "TypeScript" => "npm test",
    "javascript" => "npm test",
    "golang"     => "go test ./..."
  }.each do |language, command|
    it "reads #{language.inspect} as its table key" do
      expect(scaffold(:jenkins, OpenLanes::Setup::Stack.new(language:)).commands).to include(command)
    end
  end

  {
    "ruby"   => "bundle install",
    "node"   => "npm ci",
    "elixir" => "mix deps.get"
  }.each do |language, install|
    it "installs #{language} dependencies before lint and test, on every provider" do
      stack = OpenLanes::Setup::Stack.new(language:)
      described_class.providers.each { scaffold(it, stack).call }
      texts = described_class::PATHS.values.map { read(it) }
      expect(texts).to all(satisfy { it.index(install) && it.index(install) < it.index(described_class::COMMANDS[language].first) })
    end
  end

  it "installs the project and the python tools from pyproject.toml, else requirements.txt" do
    python = OpenLanes::Setup::Stack.new(language: "python")
    from_requirements = scaffold(:jenkins, python).install
    File.write(File.join(root, "pyproject.toml"), "")
    expect([from_requirements, scaffold(:jenkins, python).install])
      .to eq(["pip install -r requirements.txt ruff pytest", "pip install -e . ruff pytest"])
  end

  it "installs just on CircleCI and Jenkins when the commands are just recipes" do
    File.write(File.join(root, "justfile"), "lint:\n  rubocop\n\ntest:\n  rspec\n")
    %i[circleci jenkins].each { scaffold(it).call }
    expect([read(".circleci/config.yml"), read("Jenkinsfile")]).to all(include("just.systems/install.sh"))
    expect(read("Jenkinsfile")).to include("--to .bin", "PATH=$PWD/.bin:$PATH just test")
  end

  it "does not read test-unit as a test recipe" do
    File.write(File.join(root, "justfile"), "lint:\n  rubocop\n\ntest-unit:\n  rspec\n")
    expect(scaffold(:jenkins).commands).to eq(["bundle exec rubocop", "bundle exec rspec"])
  end

  it "uses an image with git and curl when the language is unknown" do
    File.write(File.join(root, "justfile"), "lint:\n  true\n\ntest:\n  true\n")
    scaffold(:github_actions, nil).call
    expect(read(".github/workflows/ci.yml")).to include("container: #{described_class::FALLBACK_IMAGE}")
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
