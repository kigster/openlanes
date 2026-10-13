# frozen_string_literal: true

# The line between `[dev]` and `[none]` on an orphan pull request. Getting it
# wrong in one direction files real work as never worth a plan — a verdict
# nobody re-opens — so the bar for asserting `[dev]` is deliberately high, and
# these examples pin exactly where it sits.
RSpec.describe OpenLanes::Plans::DevWork do
  describe ".developer?" do
    context "judged by title alone" do
      it "recognises a dependency bump for the chore it is" do
        expect(described_class.developer?("Bump rack from 3.0.1 to 3.0.2")).to be(true)
      end

      it "recognises a conventional-commit chore prefix, scoped or not" do
        aggregate_failures do
          expect(described_class.developer?("chore: tidy the justfile")).to be(true)
          expect(described_class.developer?("ci(release): sign the gem")).to be(true)
        end
      end

      it "recognises a bare version bump" do
        expect(described_class.developer?("Bump to v1.4.0")).to be(true)
      end
    end

    context "judged by the files in the diff" do
      it "asserts [dev] when every judged file is build plumbing" do
        expect(described_class.developer?("Tighten the release pipeline",
          [".github/workflows/ci.yml", "Gemfile.lock"])).to be(true)
      end

      # `.plans` and the README prove nothing either way — every pull request
      # in this tool's world touches `.plans` — so they must not be the
      # evidence that tips a real feature into [dev].
      it "ignores neutral files rather than counting them as plumbing" do
        expect(described_class.developer?("Add Schedule K-1 support",
          [".plans/004.00-🟡--k1/plan.md", "lib/k1.rb"])).to be(false)
      end

      it "refuses to judge when only neutral files remain" do
        expect(described_class.developer?("Mystery work", ["README.md", ".plans/001.00-⚪️--x/spec.md"])).to be(false)
      end

      it "refuses [dev] the moment one real source file is in the diff" do
        expect(described_class.developer?("Tweak CI", [".circleci/config.yml", "lib/openlanes/tax.rb"])).to be(false)
      end

      it "refuses [dev] with no title match and no files at all" do
        expect(described_class.developer?("Add Schedule K-1 support")).to be(false)
      end
    end
  end

  describe ".marker" do
    it "stamps asserted developer work [dev]" do
      expect(described_class.marker("chore: bump CI image")).to eq(OpenLanes::NO_PLAN_PREFIX)
    end

    # `[none]` is visibly unfinished — a job left for a human, not a verdict.
    it "stamps everything it cannot vouch for [none]" do
      expect(described_class.marker("Add Schedule K-1 support", ["lib/k1.rb"])).to eq(OpenLanes::NONE_PREFIX)
    end
  end
end
