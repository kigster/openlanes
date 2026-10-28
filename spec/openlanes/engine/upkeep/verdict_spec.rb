# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Upkeep::Verdict do
  def verdict(labels, state = "CLEAN", open: true) = described_class.of({ open:, labels:, merge_state: state })

  {
    [%w[ready-to-merge], "DIRTY"]             => :conflicted,
    [%w[review-approved conflicts], "DIRTY"]  => :still_conflicted,
    [%w[merge-manually], "BEHIND"]            => :behind,
    [%w[merge-manually conflicts], "CLEAN"]   => :resolved,
    [%w[merge-manually conflicts], "BLOCKED"] => :resolved,
    [%w[review-passed], "UNKNOWN"]            => :unknown,
    [%w[ready-to-merge], "CLEAN"]             => :none,
    [%w[review-in-progress], "DIRTY"]         => :none
  }.each do |(labels, state), expected|
    it "reads #{labels.join(" + ")} at #{state} as #{expected}" do
      expect(verdict(labels, state)).to eq(expected)
    end
  end

  it "owes nothing to a closed pull request" do
    expect(verdict(%w[ready-to-merge], "DIRTY", open: false)).to eq(:none)
  end
end
