# frozen_string_literal: true

# R3: M3's `ready-to-merge` meant review approval, so open pull requests that
# carry it move to `review-approved` before the label means chewie verified.
RSpec.describe OpenLanes::Vcs::LabelMigration do
  subject(:migration) { described_class.new(github:) }

  let(:labels) { OpenLanes::Plans::ReviewLabel }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub, swap_label: [], open_pulls_labelled: carrying) }
  let(:carrying) { [7, 9] }
  let(:colours) { { "ready-to-merge" => "2ea043", "bug" => "d73a4a" } }

  before { allow(github).to receive(:label_colours) { colours } }

  context "with a repository still on M3's ready-to-merge" do
    it "moves every open pull request carrying it to review-approved" do
      outcome = migration.call(repo: "o/r")

      aggregate_failures do
        expect(outcome).to be_pending
        expect(outcome.relabelled).to eq([7, 9])
        expect(github).to have_received(:open_pulls_labelled).with("ready-to-merge", repo: "o/r")
        [7, 9].each do |number|
          expect(github).to have_received(:swap_label)
            .with(number:, add: labels::APPROVED, remove: labels.displaced_by(labels::APPROVED), repo: "o/r")
        end
      end
    end

    it "takes ready-to-merge off as it adds review-approved" do
      migration.call

      expect(github).to have_received(:swap_label).with(hash_including(remove: include("ready-to-merge"))).twice
    end

    it "says which pull requests moved, in one line" do
      expect(migration.call.to_s).to eq("relabel ready-to-merge → review-approved on #7, #9")
    end

    it "lists them but relabels none under a dry run" do
      outcome = migration.call(dry_run: true)

      aggregate_failures do
        expect(outcome.relabelled).to eq([7, 9])
        expect(github).not_to have_received(:swap_label)
      end
    end

    # A colour neither M3's nor R3's is still not R3's: the sync has not run
    # since, so nothing can have put the new meaning on.
    it "treats any colour but R3's as M3's meaning" do
      colours["ready-to-merge"] = "abcdef"

      expect(migration.call).to be_pending
    end
  end

  context "when it was interrupted half way" do
    it "fails without the sync having run, and the next start moves only what is left" do
      allow(github).to receive(:swap_label).with(hash_including(number: 9)).and_raise(OpenLanes::Error, "HTTP 502")

      expect { migration.call }.to raise_error(OpenLanes::Error, /HTTP 502/)

      # #7 moved and no longer carries the label; the colour is still M3's.
      allow(github).to receive_messages(open_pulls_labelled: [9])
      allow(github).to receive(:swap_label).and_return([])

      aggregate_failures do
        expect(migration.call.relabelled).to eq([9])
        expect(github).to have_received(:swap_label).with(hash_including(number: 7)).once
      end
    end
  end

  context "when the sync has already given ready-to-merge R3's colour" do
    let(:colours) { { "ready-to-merge" => "5319e7" } }

    # A repeated start, or a pull request chewie has since verified: either
    # way the label now means verified, and is left where it is.
    it "does nothing, and asks GitHub for no pull requests" do
      outcome = migration.call

      aggregate_failures do
        expect(outcome).not_to be_pending
        expect(outcome.relabelled).to be_empty
        expect(outcome.to_s).to be_nil
        expect(github).not_to have_received(:open_pulls_labelled)
        expect(github).not_to have_received(:swap_label)
      end
    end

    it "compares the colour without case, as GitHub answers it" do
      colours["ready-to-merge"] = "5319E7"

      expect(migration.call).not_to be_pending
    end
  end

  context "with a repository that has no ready-to-merge label" do
    let(:colours) { { "bug" => "d73a4a" } }

    it "has nothing to migrate" do
      aggregate_failures do
        expect(migration.call).not_to be_pending
        expect(github).not_to have_received(:open_pulls_labelled)
      end
    end
  end

  # The whole start, twice over: migrate, sync, migrate, sync. The sync's
  # recolouring is what the second migration reads as done.
  it "runs once across repeated starts", :aggregate_failures do
    allow(github).to receive(:ensure_label)
    allow(github).to receive(:recolour_label) { |label, **| colours[label.name] = label.colour.downcase }
    sync = OpenLanes::Vcs::LabelSync.new(github:)

    2.times do
      migration.call
      sync.call
    end

    expect(github).to have_received(:open_pulls_labelled).once
    expect(github).to have_received(:swap_label).twice
  end
end
