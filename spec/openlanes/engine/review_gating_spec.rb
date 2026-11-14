# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Engine::ReviewGating do
  let(:builder) { instance_double(OpenLanes::Agents::Agent, builder?: true) }
  let(:reviewer) { instance_double(OpenLanes::Agents::Agent, builder?: false) }
  let(:task) { Struct.new(:agent, :root, :round).new(builder, "/checkout", 2) }
  let(:ok) { Struct.new(:ok).new(true) }
  let(:failed) { Struct.new(:ok).new(false) }
  let(:completed) { instance_double(OpenLanes::Plans::Ledger::Entry, completed?: true, round: 2) }
  let(:verdict) { OpenLanes::Engine::PreReviewGate::Verdict.new(passed: false, reason: "red", log_tail: "boom") }
  let(:gate) { class_double(OpenLanes::Engine::PreReviewGate, call: verdict) }

  def gating(**config)
    settings = OpenLanes::Config.new(**config)
    described_class.new(config: -> { settings }, gate:)
  end

  it "runs the gate in the checkout for a builder that signed Completed this round" do
    expect(gating.call(task, ok, completed)).to eq(verdict)
    expect(gate).to have_received(:call).with("/checkout")
  end

  it "passes review.gate_timeout through" do
    gating(review_gate_timeout: 60).call(task, ok, completed)
    expect(gate).to have_received(:call).with("/checkout", timeout: 60)
  end

  it "does nothing when review.gate is false" do
    expect(gating(review_gate: false).call(task, ok, completed)).to be_nil
    expect(gate).not_to have_received(:call)
  end

  it "does nothing for an agent that is not a builder" do
    expect(gating.call(task.dup.tap { it.agent = reviewer }, ok, completed)).to be_nil
  end

  it "does nothing for a failed round" do
    expect(gating.call(task, failed, completed)).to be_nil
  end

  it "does nothing when the builder signed something other than Completed" do
    blocked = instance_double(OpenLanes::Plans::Ledger::Entry, completed?: false, round: 2)
    expect(gating.call(task, ok, blocked)).to be_nil
    expect(gating.call(task, ok, nil)).to be_nil
  end

  it "does nothing for a Completed line left from an earlier round" do
    stale = instance_double(OpenLanes::Plans::Ledger::Entry, completed?: true, round: 1)
    expect(gating.call(task, ok, stale)).to be_nil
    expect(gate).not_to have_received(:call)
  end
end
