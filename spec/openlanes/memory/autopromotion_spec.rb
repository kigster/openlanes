# frozen_string_literal: true

# C1: the engine's own `memory promote`, at the end of a run. The preview,
# the publication and GitHub are all injected, so nothing here reaches git
# or the network; {Publication}'s own spec covers what the pull request holds.
RSpec.describe OpenLanes::Memory::Autopromotion do
  subject(:autopromotion) { described_class.new(preview: -> { changes }, publication: -> { published.push(true).then { result } }, github:) }

  let(:published) { [] }
  let(:open_pulls) { [] }
  let(:github) do
    double = Object.new
    rows = open_pulls
    double.define_singleton_method(:pulls) { |state:| state == "open" ? rows : raise("asked for #{state}") }
    double
  end
  let(:result) do
    OpenLanes::Memory::Publication::Result.new(branch: "memory/2026-11-20-redis-specs",
      url: "https://example.com/pr/9",
      changes:,
      held_back: [])
  end

  def change(kind, slug = "redis-specs") = OpenLanes::Memory::Promotion::Change.new(kind:, slug:, id: nil, path: nil, why: "w")

  def pull(branch:, title: "x") = { number: 9, title:, url: "https://example.com/pr/9", branch:, open: true }

  context "when a candidate is eligible" do
    let(:changes) { [change(:wait, "once"), change(:promote)] }

    it "publishes, and says where the pull request is" do
      outcome = autopromotion.call

      expect(published).to eq([true])
      expect(outcome).to have_attributes(status: :published, url: "https://example.com/pr/9", lessons: 1)
    end

    it "counts a confirmation of an existing lesson as eligible, since it lands in the pull request too" do
      changes.replace([change(:confirm)])

      expect(autopromotion.call.status).to eq(:published)
    end
  end

  context "when nothing is eligible" do
    let(:changes) { [change(:wait, "once"), change(:refuse, "leaky")] }

    it "publishes nothing and never asks GitHub" do
      allow(github).to receive(:pulls).and_call_original

      outcome = autopromotion.call

      expect(published).to eq([])
      expect(github).not_to have_received(:pulls)
      expect(outcome).to have_attributes(status: :skipped, url: nil, why: /no candidate .* is eligible/)
    end
  end

  context "when a memory pull request is already open" do
    let(:changes) { [change(:promote)] }

    it "skips, by branch, naming the open one" do
      open_pulls << pull(branch: "memory/2026-11-19-other")

      outcome = autopromotion.call

      expect(published).to eq([])
      expect(outcome).to have_attributes(status: :skipped, url: "https://example.com/pr/9", why: /still open/)
    end

    it "skips one recognised by its title, a branch renamed by hand" do
      open_pulls << pull(branch: "kig/lessons", title: "Memory: 2 lessons")

      expect(autopromotion.call.status).to eq(:skipped)
    end

    it "publishes past an open pull request that is not a memory one" do
      open_pulls << pull(branch: "hermes/045.03-split-executor", title: "[045.03] Split executor")

      expect(autopromotion.call.status).to eq(:published)
    end
  end

  context "when the publication lands nothing" do
    let(:changes) { [change(:promote)] }
    let(:result) { OpenLanes::Memory::Publication::Result.new(branch: nil, url: nil, changes:, held_back: ["lessons/x.md: line 1: anthropic"]) }

    it "reports a skip, with what the secret scan held back" do
      expect(autopromotion.call).to have_attributes(status: :skipped, url: nil, why: /1 held back/)
    end
  end
end
