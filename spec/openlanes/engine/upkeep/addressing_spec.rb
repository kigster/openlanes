# frozen_string_literal: true

# Decision U1, against a double for the GitHub seam.
RSpec.describe OpenLanes::Engine::Upkeep::Addressing do
  subject(:addressing) { described_class.new(github:) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub, swap_label: []) }
  let(:labels) { OpenLanes::Plans::ReviewLabel }
  let(:rejected_at) { Time.utc(2026, 10, 19, 10, 9, 11) }

  before do
    allow(github).to receive_messages(open_pulls_labelled: { 93 => %w[review-rejected] }, labelled_at: rejected_at)
  end

  it "labels a rejected pull request review-addressed once a commit lands after the rejection (#93)" do
    allow(github).to receive(:head_committed_at).and_return(Time.utc(2026, 10, 19, 15, 45, 48))

    aggregate_failures do
      expect(addressing.call).to eq(["PR #93 review-addressed: committed 2026-10-19T15:45:48Z, after the rejection at 2026-10-19T10:09:11Z"])
      expect(github).to have_received(:swap_label)
        .with(number: 93, add: labels::ADDRESSED, remove: labels.displaced_by(labels::ADDRESSED))
    end
  end

  it "leaves one alone whose head is older than the rejection: nothing was fixed yet" do
    allow(github).to receive(:head_committed_at).and_return(rejected_at - 60)

    aggregate_failures do
      expect(addressing.call).to be_empty
      expect(github).not_to have_received(:swap_label)
    end
  end

  it "leaves one alone that GitHub has no rejection event for" do
    allow(github).to receive(:labelled_at).and_return(nil)

    expect(addressing.call).to be_empty
  end

  it "says which pull request it could not read, and goes on with the rest" do
    allow(github).to receive(:open_pulls_labelled).and_return(93 => [], 94 => [])
    allow(github).to receive(:head_committed_at).with(number: 93).and_raise(OpenLanes::Error, "HTTP 502")
    allow(github).to receive(:head_committed_at).with(number: 94).and_return(rejected_at + 1)

    expect(addressing.call).to eq(["PR #93 not checked for fixes: HTTP 502",
                                   "PR #94 review-addressed: committed 2026-10-19T10:09:12Z, after the rejection at 2026-10-19T10:09:11Z"])
  end
end
