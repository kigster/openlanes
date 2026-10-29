# frozen_string_literal: true

require "tty/prompt/test"

# `openlanes init` asks a dozen questions; a blank line keeps them apart.
RSpec.describe OpenLanes::Setup::SpacedPrompt do
  subject(:prompt) { described_class.new(inner, out:) }

  let(:inner) { TTY::Prompt::Test.new }
  let(:out) { StringIO.new }

  before do
    ["Acme\n", "\n", "y\n", "n\n", "\n", " \n"].each { inner.input << it }
    inner.input.rewind
  end

  describe "the first question" do
    before { prompt.ask("Project name:") }

    it("follows the command line directly") { expect(out.string).to be_empty }
  end

  describe "every question after it" do
    subject(:answers) do
      [prompt.ask("Project name:"),
       prompt.select("Where a new plan starts:", %w[research planning]),
       prompt.yes?("Open to another stack?"),
       prompt.no?("Keep it?"),
       prompt.ask("Jobs:") { |q| q.default "3" },
       prompt.multi_select("Adapters:", %w[claude codex])]
    end

    it("gets the answer the prompt gave") { expect(answers).to eq(["Acme", "research", true, true, "3", %w[claude]]) }

    it "is preceded by one blank line" do
      answers
      expect(out.string).to eq("\n" * 5)
    end
  end

  it("forwards everything else to the prompt") { expect(prompt.output).to be(inner.output) }
end
