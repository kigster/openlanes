# frozen_string_literal: true

# CI on a plan's open pull requests, asked of GitHub at most once a minute.
RSpec.describe OpenLanes::Vcs::CiWatch, :tree do
  subject(:watch) { described_class.new(github:, clock: -> { now }) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }
  let(:now) { 100.0 }
  let(:pass) { { name: "test", bucket: "pass" } }
  let(:plan) do
    plans { |t| t.plan "001.00", :in_review, "in-review", prs: [t.open(7, "One"), t.merged(6, "Earlier"), t.open(8, "Two")] }
    OpenLanes::Plans::Tree.new(dir: plans_root).find("001.00")
  end

  before do
    allow(github).to receive(:checks).with(number: 7, repo: "example/repo").and_return([pass])
    allow(github).to receive(:checks).with(number: 8, repo: "example/repo").and_return([pass])
  end

  it "is green when every open pull request's checks passed, and asks about no merged one" do
    expect(watch.call(plan)).to eq(:green)
    expect(github).to have_received(:checks).twice
  end

  it "is red when any open pull request has a failed check" do
    allow(github).to receive(:checks).with(number: 8, repo: "example/repo").and_return([pass, { name: "web", bucket: "fail" }])
    expect(watch.call(plan)).to eq(:red)
  end

  it "remembers the answer for a minute" do
    watch.call(plan)
    watch.call(plan)
    expect(github).to have_received(:checks).twice
  end

  context "when the minute has passed" do
    it "asks again" do
      clock = [100.0, 161.0, 161.0].each
      fresh = described_class.new(github:, clock: -> { clock.next })
      2.times { fresh.call(plan) }
      expect(github).to have_received(:checks).exactly(4).times
    end
  end

  it "waits, and says why, when GitHub cannot be read" do
    allow(github).to receive(:checks).and_raise(OpenLanes::Error, "gh: rate limited")
    allow(OpenLanes::UI).to receive(:log)
    expect(watch.call(plan)).to eq(:pending)
    expect(OpenLanes::UI).to have_received(:log).with("could not read CI of 001.00: gh: rate limited", level: :warn, plan: "001.00")
  end
end
