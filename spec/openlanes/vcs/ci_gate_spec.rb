# frozen_string_literal: true

RSpec.describe OpenLanes::Vcs::CiGate do
  def verdict(*buckets) = described_class.verdict(buckets.map.with_index { |b, i| { name: "job#{i}", bucket: b } })

  it("is green when every check passed") { expect(verdict("pass", "pass")).to eq(:green) }
  it("is red when one failed") { expect(verdict("pass", "fail")).to eq(:red) }
  it("is red when one was cancelled") { expect(verdict("cancel")).to eq(:red) }
  it("is pending while one runs") { expect(verdict("pass", "pending")).to eq(:pending) }
  it("is red over pending when one already failed") { expect(verdict("pending", "fail")).to eq(:red) }
  it("treats a skipped job as neutral") { expect(verdict("pass", "skipping")).to eq(:green) }
  it("counts a bucket it does not know as red") { expect(verdict("pass", "stale")).to eq(:red) }
  it("says none when no check reported") { expect(verdict).to eq(:none) }
  it("says none when every check was skipped, as when CI did not run") { expect(verdict("skipping", "skipping")).to eq(:none) }
end
