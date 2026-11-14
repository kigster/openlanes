# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Engine::PreReviewGate, :real_gate do
  around do |example|
    Dir.mktmpdir("gate") do |dir|
      @checkout = dir
      example.run
    end
  end

  attr_reader :checkout

  it "passes when every command exits 0" do
    verdict = described_class.call(checkout, commands: ["true", "echo fine"])
    expect(verdict).to be_passed
    expect(verdict.log_tail).to eq("")
  end

  it "stops at the first red command and keeps its output's tail" do
    verdict = described_class.call(checkout, commands: ["echo boom; exit 3", "touch ran"])
    expect(verdict).not_to be_passed
    expect(verdict.reason).to include("exited 3")
    expect(verdict.log_tail).to include("boom")
    expect(File).not_to exist(File.join(checkout, "ran"))
  end

  it "keeps only the last TAIL lines" do
    verdict = described_class.call(checkout, commands: ["seq 1 100; exit 1"])
    expect(verdict.log_tail.lines.size).to eq(described_class::TAIL)
    expect(verdict.log_tail.lines.last.strip).to eq("100")
  end

  it "runs in the checkout" do
    described_class.call(checkout, commands: ["touch here"])
    expect(File).to exist(File.join(checkout, "here"))
  end

  it "calls a command that outlives its timeout red" do
    verdict = described_class.call(checkout, commands: ["sleep 5"], timeout: 0.2)
    expect(verdict).not_to be_passed
    expect(verdict.reason).to include("timed out")
  end

  it "passes a checkout with nothing it recognises" do
    verdict = described_class.call(checkout)
    expect(verdict).to be_passed
    expect(verdict.reason).to eq("no checks found")
  end

  it "derives the command from the justfile's check-all recipe" do
    skip "just is not installed" unless system("command -v just >/dev/null 2>&1")

    File.write(File.join(checkout, "justfile"), "check-all:\n    @echo red suite; exit 1\n")
    verdict = described_class.call(checkout)
    expect(verdict).not_to be_passed
    expect(verdict.reason).to include("just check-all")
    expect(verdict.log_tail).to include("red suite")
  end
end
