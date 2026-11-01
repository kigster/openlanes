# frozen_string_literal: true

require "tty-prompt"

RSpec.describe OpenLanes::Lifecycle::ReasonInterview, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:out) { CapturedStream.new }
  let(:choices) { described_class::TRASH_CHOICES }

  before do
    plans do |t|
      t.plan "003.00", :new, "tax-rule-dsl", files: { "spec.md" => spec_body }
      t.plan "007.00", :new, "other", files: { "spec.md" => spec_body }
    end
  end

  def interview(verb, choices: nil) = described_class.new(prompt:, verb:, choices:, out:)

  it "offers trash exactly the five choices, the first as the default" do
    expect(choices).to eq([
                            "This plan is already implemented, but outside of OpenLanes",
                            "This plan conflicts with another plan so we are scrapping it",
                            "This plan is no longer relevant",
                            "This plan is poorly spec'd and needs to be re-started anew",
                            "Some other reason"
                          ])
    allow(prompt).to receive(:select).with("Why are we trashing it today?", choices, default: choices.first).and_return(choices[2])
    answers = interview("trashing", choices:).ask([tree.find("003.00")])
    expect(answers).to eq({ "003.00" => choices[2] })
  end

  it "names each plan with its title and state" do
    allow(prompt).to receive(:select).and_return(choices.first)
    interview("trashing", choices:).ask(tree.subjects)
    expect(strip_ansi(out.string)).to include("Trashing plans [ 003.00, 007.00 ]:", "1. Plan 003.00: Tax Rule DSL", "State: ⚪ New", "2. Plan 007.00")
  end

  it "asks for free text after Some other reason, and refuses a blank one" do
    allow(prompt).to receive(:select).and_return("Some other reason")
    allow(prompt).to receive(:ask).with("Reason for scrapping this plan:").and_return("  ", nil, "because")
    expect(interview("trashing", choices:).ask([tree.find("003.00")])).to eq({ "003.00" => "because" })
    expect(prompt).to have_received(:ask).exactly(3).times
  end

  it "asks discard for free text only" do
    allow(prompt).to receive(:ask).with("Please provide a reason for discarding this plan:").and_return("", "no longer wanted")
    expect(interview("discarding").ask([tree.find("003.00")])).to eq({ "003.00" => "no longer wanted" })
  end

  it "words abandon as abandoning" do
    allow(prompt).to receive(:ask).with("Please provide a reason for abandoning this plan:").and_return("stalled")
    expect(interview("abandoning").ask([tree.find("003.00")])).to eq({ "003.00" => "stalled" })
  end
end
