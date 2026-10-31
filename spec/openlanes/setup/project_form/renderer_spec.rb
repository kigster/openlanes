# frozen_string_literal: true

require "tty/prompt/test"

RSpec.describe OpenLanes::Setup::ProjectForm::Renderer do
  subject(:renderer) { described_class.new(prompt:, out:, width: 40, preselect:) }

  let(:prompt) { TTY::Prompt::Test.new }
  let(:out) { StringIO.new }
  let(:preselect) { ->(_id) {} }
  let(:definition) { OpenLanes::Setup::ProjectForm.definition }
  let(:drawn) { [prompt.output.string, out.string].flat_map(&:lines).map { it.gsub(/\e\[[0-9;?]*[A-Za-z]/, "").chomp.length } }

  def press(*keys) = keys.each { prompt.input << it }.then { prompt.input.rewind }

  context "with a multi-select" do
    let(:preselect) { ->(id) { %w[circleci github_actions] if id == :target_ci } }

    before { press("\n") }

    it "submits what was preselected" do
      expect(renderer.render(definition.step(:target_ci))).to contain_exactly("github_actions", "circleci")
    end

    it "echoes the answer on a line of its own" do
      renderer.render(definition.step(:target_ci))
      expect(out.string).to include("Space selects").and include("circleci, github actions")
    end

    it "takes Enter with nothing chosen" do
      expect(renderer.render(definition.step(:target_caching))).to eq([])
      expect(out.string).to include("nothing yet")
    end

    it "keeps an answer given before going back over the preselection" do
      expect(renderer.render(definition.step(:target_ci), default: %w[jenkins])).to eq(%w[jenkins])
    end
  end

  context "with a single select" do
    before { press("\n") }

    it "falls back to the step's own default" do
      expect(renderer.render(definition.step(:detail))).to eq("medium")
    end

    it "draws no line past the width, the choices' words included" do
      renderer.render(definition.step(:desired_codebase_quality))
      expect(drawn).to all(be <= 40)
    end
  end

  context "with a collected step" do
    let(:engine) { OpenLanes::Setup::ProjectForm.engine }

    before { press("\n") }

    it "prints its hint on the prompt's stream, never on STDOUT" do
      expect { renderer.collect(engine) }.not_to output.to_stdout
      expect(out.string).to include("skip")
    end
  end

  context "with a long text question" do
    before do
      engine = OpenLanes::Setup::ProjectForm.engine
      engine.answer("low")
      press("a shop\n", "\n")
      renderer.render(engine.current_step)
    end

    it "keeps its hints and rules inside the width" do
      expect(out.string.lines.map { strip_ansi(it).chomp.length }).to all(be <= 40)
    end
  end

  it "takes the terminal's width by default" do
    expect(described_class.new(prompt:)).to be_a(Inquirex::TTY::Renderer)
  end
end
