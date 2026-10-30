# frozen_string_literal: true

require "tty/prompt/test"

RSpec.describe OpenLanes::Setup::Interview do
  let(:root) { File.join(Dir.mktmpdir("openlanes-interview"), "acme") }
  let(:prompt) { TTY::Prompt::Test.new }
  let(:out) { StringIO.new }
  let(:extractor) { nil }
  let(:given) { {} }

  before { FileUtils.mkdir_p(root) }
  after { FileUtils.rm_rf(File.dirname(root)) }

  def terminal = OpenLanes::Setup::ProjectForm::Terminal.new(prompt:, extractor:, out:)

  def interview(**) = described_class.new(root:, given:, terminal:, **)

  def unasked(**) = described_class.new(root:, given:, **)

  def touch(name, text = "")
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def press(*keys) = keys.each { prompt.input << it }.then { prompt.input.rewind }

  context "when asking, in a folder with CI and a stack" do
    subject(:config) { interview.call }

    before do
      touch(".github/workflows/ci.yml")
      touch(".circleci/config.yml")
      touch("Gemfile")
      touch("Gemfile.lock", "GEM\n  specs:\n    rails (8.0.1)\n")
      press(*Array.new(40, "\n"))
    end

    it "preselects both CIs, and records them" do
      expect(config.architecture_decisions.current.ci).to contain_exactly(:github_actions, :circleci)
    end

    it "names the project after its folder" do
      expect(config.project).to eq("acme")
    end

    it "records the detail chosen and the quality offered first" do
      expect([config.architecture_decisions.detail, config.desired_codebase_quality]).to eq(%i[medium high])
    end

    it "writes neither of the old keys" do
      expect([config.ci, config.stack]).to eq([nil, nil])
    end

    it "asks what the folder holds now" do
      config
      expect(strip_ansi(out.string + prompt.output.string)).to include("NOW, CI")
    end
  end

  context "when asking, with flags" do
    let(:given) { { project: "Flagged", merge_by: :auto, desired_codebase_quality: :mvp, starts: "building", jobs: 3 } }

    before { press(*Array.new(40, "\n")) }

    it "takes each flag without asking" do
      expect(interview.call).to have_attributes(project: "Flagged", merge_by: :auto, desired_codebase_quality: :mvp, starts: :building, jobs: 3)
      expect(strip_ansi(prompt.output.string)).not_to match(/Project name|merges|desired quality|new plan starts|Plans to run/)
    end
  end

  context "when asking, in an empty folder" do
    before { press(*Array.new(40, "\n")) }

    it "does not ask what it holds" do
      interview.call
      expect(strip_ansi(prompt.output.string)).not_to include("NOW,")
    end

    context "with a front end wanted or ruled out" do
      def wanted(front_end)
        preselection = instance_double(OpenLanes::Setup::ProjectForm::Answers,
          decisions: OpenLanes::Setup::ArchitectureDecisions.new(detail: nil,
            migration: nil,
            current: OpenLanes::Setup::Architecture.new,
            target: OpenLanes::Setup::Architecture.new(front_end:)))
        allow(OpenLanes::Setup::ProjectForm::Answers).to receive(:new).and_return(preselection)
        unasked.call.frontend
      end

      it "reads it from what is wanted" do
        expect([wanted(%w[react]), wanted(%w[none])]).to eq([true, false])
      end
    end
  end

  context "without asking" do
    it "records the scan, and leaves quality unset" do
      touch("Cargo.toml")
      expect(unasked.call).to have_attributes(
        merge_by:                 :human,
        desired_codebase_quality: nil,
        starts:                   :research,
        architecture_decisions:   have_attributes(detail: nil, current: have_attributes(languages: %i[rust]))
      )
    end

    it "builds no extractor's worth of questions" do
      expect(unasked.call.architecture_decisions).to be_nil
    end

    it "moves an older file's ci: and stack: over" do
      current = OpenLanes::Config.new(desired_codebase_quality: :mvp, merge_by: :auto, stack: { language: "elixir" }, ci: { provider: :external, config: nil })
      expect(unasked(defaults: current).call).to have_attributes(
        ci:                       nil,
        stack:                    nil,
        merge_by:                 :auto,
        desired_codebase_quality: :mvp,
        architecture_decisions:   have_attributes(target: have_attributes(ci: %i[external], languages: %i[elixir]))
      )
    end

    it "keeps every key it does not ask about" do
      current = OpenLanes::Config.new(redis_url: "redis://cache.example.test:6379",
        merge_max_rejections: 3,
        questions_model: "claude-sonnet-4-5",
        redis_outage_hours: 4,
        frontend: true,
        commands: { lint: { run: "x" } })
      expect(unasked(defaults: current).call).to have_attributes(
        redis_url:            "redis://cache.example.test:6379",
        merge_max_rejections: 3,
        questions_model:      "claude-sonnet-4-5",
        redis_outage_hours:   4,
        frontend:             true,
        commands:             { lint: { run: "x" } }
      )
    end

    it "keeps the flag for a front end" do
      expect(described_class.new(root:, given: { frontend: false }).call.frontend).to be(false)
    end

    it "takes a blank count as none" do
      expect(described_class.new(root:, given: { jobs: " " }).call.jobs).to be_nil
    end

    it "refuses jobs that are not a count" do
      expect { described_class.new(root:, given: { jobs: "many" }).call }.to raise_error(OpenLanes::Error, /jobs/)
    end
  end
end
