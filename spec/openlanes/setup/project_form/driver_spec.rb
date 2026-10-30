# frozen_string_literal: true

require "tty/prompt/test"

RSpec.describe OpenLanes::Setup::ProjectForm::Driver do
  subject(:answers) { driver.call(engine) }

  let(:architecture) { OpenLanes::Setup::Architecture }
  let(:prompt) { TTY::Prompt::Test.new }
  let(:out) { StringIO.new }
  let(:engine) { OpenLanes::Setup::ProjectForm.engine }
  let(:extractor) { nil }
  let(:prefilled) { { greenfield: true, project: "Acme", jobs: 2 } }
  let(:preselection) do
    OpenLanes::Setup::ProjectForm::Preselection.new(scan: architecture.new, file: OpenLanes::Setup::ArchitectureDecisions.none)
  end
  let(:renderer) do
    OpenLanes::Setup::ProjectForm::Renderer.new(prompt:, out:, width: 100, preselect: ->(id) { preselection.for(id, engine.answers) })
  end
  let(:driver) { described_class.new(renderer:, preselection:, prefilled:, terminal: OpenLanes::Setup::ProjectForm::Terminal.new(prompt:, extractor:, out:)) }

  def press(*keys) = keys.each { prompt.input << it }.then { prompt.input.rewind }

  before { press(*Array.new(40, "\n")) }

  context "with nothing to read a description" do
    it "says so, and walks to the end" do
      expect(answers).to include(project: "Acme", jobs: 2, detail: "medium", merge_by: "human", no_extraction: true)
      expect(out.string).to include(described_class::NO_ROUTE.split.first)
    end

    it "does not ask for a description" do
      answers
      expect(strip_ansi(prompt.output.string)).not_to include("Describe what you are building")
    end

    it "leaves one blank line between questions" do
      answers
      hints = strip_ansi(out.string).lines.each_cons(2).select { |_, line| line.include?("^S skip") }
      expect(hints.map(&:first)).to all(eq("\n"))
    end

    it "does not ask an empty folder what it holds" do
      answers
      expect(strip_ansi(prompt.output.string)).not_to include("NOW,")
    end
  end

  context "with a description to read" do
    let(:extractor) do
      instance_double(OpenLanes::Setup::Extractor, label: "a test", call: { target_ci: %w[jenkins], merge_by: "auto" })
    end

    before do
      prompt.input.truncate(0)
      prompt.input.rewind
      press("\n", "a shop\n", "\n", *Array.new(40, "\n"))
    end

    it "says where it goes before asking" do
      answers
      expect(out.string).to include("Your description goes to a test")
    end

    it "preselects what it settled" do
      expect(answers).to include(target_ci: %w[jenkins], merge_by: "auto")
    end

    it "reads the description it was given" do
      answers
      expect(extractor).to have_received(:call).with(anything, "a shop")
    end
  end

  context "with an answer the validator refuses" do
    before do
      call = 0
      allow(renderer).to receive(:collect).and_wrap_original do |original, *args|
        call += 1
        raise Inquirex::Errors::ValidationError, "Validation failed: no" if call == 1

        original.call(*args)
      end
    end

    it "reports it and asks the same question again" do
      expect(answers).to include(detail: "medium")
      expect(out.string).to include("Validation failed: no")
    end
  end
end
