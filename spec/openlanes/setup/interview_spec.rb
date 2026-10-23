# frozen_string_literal: true

require "tty/prompt/test"

RSpec.describe OpenLanes::Setup::Interview do
  let(:root) { File.join(Dir.mktmpdir("openlanes-interview"), "acme") }
  let(:prompt) { TTY::Prompt::Test.new }
  let(:out) { StringIO.new }
  let(:extractor) { nil }
  let(:given) { { project: "Acme", lane: "full", frontend: false, jobs: 2 } }
  # Keys for TTY::Prompt::Test: Enter takes the highlighted choice or the default.
  let(:enter) { "\r" }
  let(:down) { "\e[B" }

  before { FileUtils.mkdir_p(root) }
  after { FileUtils.rm_rf(File.dirname(root)) }

  def interview(ask: true, **) = described_class.new(root:, prompt:, extractor:, given:, ask:, out:, **)

  def touch(name, text = "")
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def answer(*keys) = keys.each { prompt.input << it }.then { prompt.input.rewind }

  def asked = strip_ansi(prompt.output.string)

  context "with a CI and a stack already in the folder, no key" do
    before do
      touch(".github/workflows/ci.yml")
      touch("Gemfile")
      touch("Gemfile.lock", "GEM\n  specs:\n    rails (8.0.1)\n")
      # merge (Enter: human), quality (Down, Enter: mvp), eight stack questions (Enter each),
      # open to another stack (n)
      answer(enter, down, enter, *Array.new(8, "\n"), "n\n")
    end

    it "names the CI and asks nothing about it" do
      config = interview.call
      expect([config.ci, out.string, asked]).to match([
                                                        { provider: :github_actions, config: ".github/workflows/ci.yml" },
                                                        include("CI: found GitHub Actions"), satisfy { !it.include?("CI setup") }
                                                      ])
    end

    it "says once that no key can read a description, and asks every question" do
      config = interview.call
      expect([out.string.scan(described_class::NO_KEY).size, asked.include?("Describe the app")]).to eq([1, false])
      expect(config).to have_attributes(merge_by: :human,
        desired_codebase_quality: :mvp,
        stack: { language: "ruby", frameworks: ["rails"] })
    end

    it "asks in order: merge, quality, stack, port" do
      interview.call
      marks = ["Who merges", "desired quality", "Language:", "Domain:", "open to a different stack"]
      expect(marks.map { asked.index(it) }).to eq(marks.map { asked.index(it) }.sort)
    end
  end

  context "with no CI" do
    it "records an external CI" do
      answer(enter)
      expect(interview.send(:settle_ci)).to eq(provider: :external, config: nil)
    end

    it "records none" do
      answer(down, down, enter)
      expect(interview.send(:settle_ci)).to eq(provider: :none, config: nil)
    end

    it "offers to set one up, GitHub Actions first" do
      answer(down, enter, down, enter)
      expect([interview.send(:settle_ci), asked]).to match([
                                                             { provider: :circleci, config: ".circleci/config.yml" },
                                                             include("CI setup", "GitHub Actions", "CircleCI", "Jenkins")
                                                           ])
    end
  end

  context "with an extractor" do
    let(:extractor) { instance_double(OpenLanes::Setup::Extractor) }

    before do
      allow(extractor).to receive(:call).with("A payroll app in Go")
                                        .and_return(merge_by: :auto, desired_codebase_quality: :mvp, language: "go")
      # CI: No CI for now; description; seven stack questions left
      answer(down, down, enter, "A payroll app in Go\n", *Array.new(7, "\n"))
    end

    it "skips every question the description answered" do
      config = interview.call
      expect([config.merge_by, config.desired_codebase_quality, config.stack]).to eq([:auto, :mvp, { language: "go" }])
      expect(["Who merges", "desired quality", "Language:"].map { asked.include?(it) }).to eq([false, false, false])
    end
  end

  context "when porting a detected stack" do
    before do
      touch("Jenkinsfile")
      touch("go.mod")
      answer(enter, enter, *Array.new(8, "\n"), "y\n", enter, "rust\n")
    end

    it "records from and to" do
      expect(interview.call.stack).to include(language: "go", from: "go", to: "rust")
    end
  end

  context "when starting fresh beside a detected stack" do
    before do
      touch("Jenkinsfile")
      touch("go.mod")
      answer(enter, enter, *Array.new(8, "\n"), "y\n", down, enter)
    end

    it "records no port" do
      expect(interview.call.stack).to eq(language: "go")
    end
  end

  context "with a mixed stack" do
    before do
      touch("Jenkinsfile")
      touch("Gemfile")
      touch("go.mod")
      answer(enter, enter, "go\n", *Array.new(7, "\n"))
    end

    it "says so and asks, with no default" do
      expect([interview.call.stack, out.string]).to match([{ language: "go" }, include("ruby, go")])
    end
  end

  context "without asking" do
    let(:prompt) { nil }

    it "takes the defaults and the detected stack" do
      touch("Cargo.toml")
      expect(interview(ask: false).call).to have_attributes(
        ci: { provider: :none, config: nil }, merge_by: :human, desired_codebase_quality: nil, stack: { language: "rust" }
      )
    end

    it "keeps the current file's answers" do
      current = OpenLanes::Config.new(desired_codebase_quality: :mvp,
        merge_by: :auto,
        stack: { language: "elixir" },
        ci: { provider: :external, config: nil })
      expect(interview(ask: false, defaults: current).call).to have_attributes(
        ci:            { provider: :external, config: nil },
        merge_by:      :auto,
        desired_codebase_quality: :mvp,
        stack:         { language: "elixir" }
      )
    end

    it "leaves a mixed stack unset" do
      touch("Gemfile")
      touch("go.mod")
      expect(interview(ask: false).call.stack).to be_nil
    end

    it "refuses jobs that are not a count" do
      expect { interview(ask: false, given: { jobs: "many" }).call }.to raise_error(OpenLanes::Error, /jobs/)
    end
  end
end
