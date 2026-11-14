# frozen_string_literal: true

# `review-in-progress` on a pull request nobody is reviewing, against a
# double for the GitHub seam and a real `.plans` tree.
RSpec.describe OpenLanes::Engine::Upkeep::Finishing, :tree do
  subject(:finishing) { described_class.new(github:) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub, remove_label: nil) }
  let(:closed) { { 7 => %w[openlanes review-in-progress] } }
  let(:open) { { 1 => %w[review-in-progress], 2 => %w[review-in-progress], 9 => %w[review-in-progress] } }

  def subjects = OpenLanes::Plans::Tree.new(dir: plans_root).subjects

  before do
    plans do |t|
      t.plan "031.00", :in_review, "being-reviewed", files: { "spec.md" => spec_body }, prs: [t.open(1, "Being reviewed")]
      t.plan "032.00", :rejected, "sent-back", files: { "spec.md" => spec_body }, prs: [t.open(2, "Sent back")]
    end
    allow(github).to receive(:pulls_labelled).with("review-in-progress", state: "closed").and_return(closed)
    allow(github).to receive(:open_pulls_labelled).with("review-in-progress").and_return(open)
  end

  it "takes the label off a merged or closed pull request, and off an open one whose plan has left review" do
    aggregate_failures do
      expect(finishing.call(subjects)).to eq(["PR #7: review-in-progress taken off, nobody is reviewing it",
                                              "PR #2: review-in-progress taken off, nobody is reviewing it"])
      expect(github).to have_received(:remove_label).with(number: 7, name: "review-in-progress")
      expect(github).to have_received(:remove_label).with(number: 2, name: "review-in-progress")
    end
  end

  it "leaves one that is being reviewed, and one no plan of this run opened" do
    finishing.call(subjects)

    aggregate_failures do
      expect(github).not_to have_received(:remove_label).with(number: 1, name: "review-in-progress")
      expect(github).not_to have_received(:remove_label).with(number: 9, name: "review-in-progress")
    end
  end

  it "does not ask about the open ones when every plan with a pull request is in review" do
    finishing.call(subjects.select { it.status.key == :in_review })

    expect(github).not_to have_received(:open_pulls_labelled)
  end

  it "says which pull request kept the label, and goes on with the rest" do
    allow(github).to receive(:remove_label).with(number: 7, name: "review-in-progress").and_raise(OpenLanes::Error, "gh is down\nmore")

    expect(finishing.call(subjects)).to eq(["PR #7 still review-in-progress: gh is down",
                                            "PR #2: review-in-progress taken off, nobody is reviewing it"])
  end
end
