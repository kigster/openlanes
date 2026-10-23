# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::StackDetector do
  subject(:detection) { described_class.new(root).call }

  let(:root) { Dir.mktmpdir("openlanes-stack") }

  after { FileUtils.rm_rf(root) }

  def touch(name, text = "")
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  {
    "Gemfile"          => "ruby",
    "package.json"     => "node",
    "go.mod"           => "go",
    "Cargo.toml"       => "rust",
    "mix.exs"          => "elixir",
    "pyproject.toml"   => "python",
    "requirements.txt" => "python"
  }.each do |marker, language|
    it "reads #{marker} as #{language}" do
      touch(marker, marker == "package.json" ? "{}" : "")
      expect([detection.languages, detection.stack.language, detection.mixed?]).to eq([[language], language, false])
    end
  end

  it "refines Ruby with the frameworks Gemfile.lock names" do
    touch("Gemfile")
    touch("Gemfile.lock", "GEM\n  specs:\n    rails (8.0.1)\n    sinatra (4.1.0)\n    railties (8.0.1)\n")
    expect(detection.stack.frameworks).to eq(%w[rails sinatra])
  end

  it "does not read a gem whose name only starts like a framework" do
    touch("Gemfile")
    touch("Gemfile.lock", "GEM\n  specs:\n    railties (8.0.1)\n")
    expect(detection.stack.frameworks).to eq([])
  end

  it "refines Node with its dependencies, and names react as the front end" do
    touch("package.json",
      JSON.dump("dependencies" => { "react" => "19", "next" => "15" },
        "devDependencies" => { "vite" => "6" }))
    expect(detection.stack).to have_attributes(frameworks: %w[next vite], front_end: "react")
  end

  it "reads astro and vite config files as frameworks" do
    touch("package.json", "{}")
    touch("astro.config.mjs")
    touch("vite.config.ts")
    expect(detection.stack.frameworks).to eq(%w[astro vite])
  end

  it "survives a package.json that is not JSON" do
    touch("package.json", "{ nope")
    expect(detection.stack).to have_attributes(language: "node", frameworks: [])
  end

  it "refines Python with fastapi or django" do
    touch("requirements.txt", "Django==5.1\nfastapi\n")
    expect(detection.stack.frameworks).to eq(%w[fastapi django])
  end

  it "finds nothing in an empty folder" do
    expect([detection.languages, detection.stack, detection.mixed?, detection.hints]).to eq([[], nil, false, []])
  end

  it "reports two languages as mixed, with no stack" do
    touch("Gemfile")
    touch("go.mod")
    expect([detection.languages, detection.stack, detection.mixed?]).to eq([%w[ruby go], nil, true])
  end

  it "keeps Dockerfile and .tool-versions as hints only" do
    touch("Dockerfile")
    touch(".tool-versions")
    expect([detection.hints, detection.languages]).to eq([%w[Dockerfile .tool-versions], []])
  end

  describe OpenLanes::Setup::Stack do
    it "leaves unanswered fields out of to_h" do
      expect(described_class.new(language: "ruby", frameworks: []).to_h).to eq(language: "ruby")
    end

    it "builds from the config's shape, string keys included" do
      expect(described_class.from_h("language" => "go", "to" => "rust")).to have_attributes(language: "go", to: "rust")
    end

    it "is empty when nothing was answered" do
      expect([described_class.new.empty?, described_class.from_h(nil).empty?]).to eq([true, true])
    end
  end
end
