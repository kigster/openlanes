# frozen_string_literal: true

# R3: M3's review labels come off open pull requests, onto R3's, once per
# repository, before anything reads `ready-to-merge` as verifier's verification.
#
# The double below is a tiny GitHub: open pull requests and their labels, and
# the repository's labels, which the migration reads and changes the way the
# real one would.
RSpec.describe OpenLanes::Vcs::LabelMigration do
  subject(:migration) { described_class.new(github:) }

  let(:labels) { OpenLanes::Plans::ReviewLabel }
  let(:marker) { labels::MIGRATED.name }
  let(:repository) { { "ready-to-merge" => "5319e7", "bug" => "d73a4a" } }
  let(:pulls) do
    {
      7  => ["ready-to-merge"],
      9  => %w[ready-to-merge enhancement],
      11 => ["review-passed"],
      12 => ["ok-to-merge"],
      13 => %w[ok-to-merge ready-to-merge],
      14 => ["review-rejected"]
    }
  end
  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }
  let(:fail_on) { [] }

  before do
    allow(github).to receive(:label_colours) { repository.dup }
    allow(github).to receive(:open_pulls_labelled) { |name, **| pulls.select { |_, on| on.include?(name) }.transform_values(&:dup) }
    allow(github).to receive(:ensure_label) { |label, **| repository[label.name] ||= label.colour }
    allow(github).to receive(:swap_label) do |number:, add:, remove:, **|
      raise OpenLanes::Error, "could not label ##{number}: HTTP 502" if fail_on.include?(number)

      pulls[number] = (pulls[number] - remove) | [add.name]
    end
  end

  def verdicts(number) = pulls[number] & (labels.known + ["enhancement"])

  context "with a repository an earlier release already recoloured" do
    # The colour is R3's, but no pull request was ever moved: kigster/openlanes.
    it "migrates anyway, because only the marker says it is done" do
      outcome = migration.call(repo: "o/r")

      aggregate_failures do
        expect(outcome).to be_pending
        expect(verdicts(7)).to eq(["review-approved"])
        expect(verdicts(9)).to eq(%w[enhancement review-approved])
      end
    end
  end

  # V2 gave R3's ok-not-perfect verdict M3's name back, meaning the same.
  it "leaves M3's review-passed where it is" do
    migration.call

    expect(verdicts(11)).to eq(["review-passed"])
  end

  it "carries M3's verification over to ready-to-merge, whatever else the pull request carried" do
    migration.call

    aggregate_failures do
      expect(verdicts(12)).to eq(["ready-to-merge"])
      expect(verdicts(13)).to eq(["ready-to-merge"])
    end
  end

  it "leaves a pull request with no M3 label alone" do
    migration.call

    expect(verdicts(14)).to eq(["review-rejected"])
  end

  it "marks the repository done after the last step, and says what moved in one line" do
    outcome = migration.call

    aggregate_failures do
      expect(repository).to include(marker)
      expect(outcome.to_s).to eq("relabel ready-to-merge → review-approved on #7, #9; " \
                                 "ok-to-merge → ready-to-merge on #12, #13")
    end
  end

  it "creates each label it adds once, not once per pull request" do
    migration.call

    aggregate_failures do
      expect(github).to have_received(:ensure_label).with(labels::APPROVED, repo: nil).once
      expect(github).to have_received(:swap_label).with(hash_including(create_missing: false)).at_least(:once)
      expect(github).not_to have_received(:swap_label).with(hash_including(create_missing: true))
    end
  end

  it "reports every move under a dry run, and changes nothing" do
    before = pulls.transform_values(&:dup)
    outcome = migration.call(dry_run: true)

    aggregate_failures do
      expect(outcome.relabelled).to eq([7, 9, 12, 13])
      expect(pulls).to eq(before)
      expect(repository).not_to include(marker)
      expect(github).not_to have_received(:swap_label)
    end
  end

  context "when it is interrupted half way" do
    it "leaves the repository unmarked, and the next start moves only what is left" do
      fail_on << 9
      expect { migration.call }.to raise_error(OpenLanes::Error, /HTTP 502/)
      expect(repository).not_to include(marker)

      fail_on.clear
      outcome = migration.call

      aggregate_failures do
        expect(outcome.moves.values.first).to eq([9])
        expect(github).to have_received(:swap_label).with(hash_including(number: 7)).once
        expect(repository).to include(marker)
      end
    end

    # The third step put ready-to-merge on #12 and kept ok-to-merge; a start
    # after that must not read #12's ready-to-merge as M3's.
    it "keeps a verification carried over before the interruption" do
      allow(github).to receive(:ensure_label).with(labels::MIGRATED, repo: nil).and_raise(OpenLanes::Error, "HTTP 502")
      expect { migration.call }.to raise_error(OpenLanes::Error, /HTTP 502/)
      expect(pulls[12]).to include("ok-to-merge", "ready-to-merge")

      allow(github).to receive(:ensure_label) { |label, **| repository[label.name] ||= label.colour }
      migration.call

      expect(verdicts(12)).to eq(["ready-to-merge"])
    end
  end

  it "keeps the mark when only taking ok-to-merge off fails" do
    allow(github).to receive(:swap_label).with(hash_including(remove: ["ok-to-merge"])).and_raise(OpenLanes::Error, "HTTP 502")

    aggregate_failures do
      expect { migration.call }.not_to raise_error
      expect(repository).to include(marker)
      expect(pulls[12]).to include("ready-to-merge")
    end
  end

  context "with a repository already marked" do
    before { repository[marker] = labels::MIGRATED.colour }

    # A repeated start, or a ready-to-merge verifier has since put on: either
    # way it means verified, and is left where it is.
    it "does nothing, and asks GitHub for no pull requests" do
      outcome = migration.call

      aggregate_failures do
        expect(outcome).not_to be_pending
        expect(outcome.to_s).to be_nil
        expect(github).not_to have_received(:open_pulls_labelled)
        expect(github).not_to have_received(:swap_label)
      end
    end
  end

  it "runs once across repeated starts" do
    2.times { migration.call }

    expect(github).to have_received(:open_pulls_labelled).with("ready-to-merge", repo: nil).once
  end

  context "with a repository that never had M3's labels" do
    let(:pulls) { {} }

    it "moves nothing and marks it done" do
      aggregate_failures do
        expect(migration.call.relabelled).to be_empty
        expect(repository).to include(marker)
      end
    end
  end
end
