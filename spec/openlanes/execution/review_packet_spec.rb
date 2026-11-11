# frozen_string_literal: true

# The packet is read through a doubled `gh` seam and a real plan folder: what
# matters is the text three reviewers get, and that GitHub is asked once.
RSpec.describe OpenLanes::Execution::ReviewPacket, :tree do
  subject(:packet) { described_class.new(github:, dir: packets, **limits) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub, diff: diff) }
  let(:packets) { Dir.mktmpdir("packets") }
  let(:limits) { {} }
  let(:diff) { "#{file_diff("lib/a.rb")}#{file_diff("lib/b.rb")}" }
  let(:prs) { [{ number: 12, title: "Add the thing", url: "https://github.com/example/repo/pull/12", state: "open" }] }
  let(:files) { { "spec.md" => spec_body, "plan.md" => "## Units\n\nU1 builds it.\n", "contract.md" => "## API\n" } }
  let(:plan) do
    plans { |t| t.plan "007.00", :in_review, "thing", files:, prs: }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end

  after { FileUtils.rm_rf(packets) }

  def file_diff(path, lines: 3)
    "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n@@ -0,0 +1,#{lines} @@\n#{"+added line\n" * lines}"
  end

  it "carries the plan's documents and the pull request's diff" do
    text = packet.call(plan)

    expect(text).to start_with("# Review packet")
    expect(text).to include('<document name="spec.md">',
      "Make the thing work, end to end.",
      '<document name="plan.md">',
      "U1 builds it.",
      '<document name="contract.md">',
      '<document name="pull-requests.md">',
      "<diff pr=\"12\">\ndiff --git a/lib/a.rb b/lib/a.rb",
      "End of the review packet.")
    expect(text).not_to include("was cut", "implementation-plan.md")
  end

  it "asks gh for the diff of the pull request's own repository" do
    packet.call(plan)

    expect(github).to have_received(:diff).with(number: "12", repo: "example/repo")
  end

  it "builds one packet for a round, whoever asks and whatever was written since" do
    first = packet.call(plan)
    File.write(File.join(plan.feature.path, "pull-requests.md"), "## Findings: staff-reviewer\n", mode: "a")
    later = described_class.new(github:, dir: packets).call(OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first)

    expect(later).to eq(first)
    expect(github).to have_received(:diff).once
  end

  it "builds a new packet once the folder has moved, and drops the old one" do
    packet.call(plan)
    moved = plan.machine.promote!(:rejected).then { OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first }
    File.write(File.join(moved.feature.path, "plan.md"), "## Units\n\nU1 was fixed.\n")

    expect(packet.call(moved)).to include("U1 was fixed.")
    expect(github).to have_received(:diff).twice
    expect(Dir.children(packets).size).to eq(1)
  end

  it "reads implementation-plan.md where an old folder has no contract" do
    files.delete("contract.md")
    files["implementation-plan.md"] = "## Steps\n"

    text = packet.call(plan)

    expect(text).to include('<document name="implementation-plan.md">')
    expect(text).not_to include('name="contract.md"')
  end

  it "is what the facade hands an executor, asking gh from the given checkout" do
    allow(OpenLanes::Vcs::GitHub).to receive(:new).with(chdir: "/repo").and_return(github)

    expect(OpenLanes::Execution.review_packets(root: "/repo")).to be_a(described_class)
  end

  context "when the diff is larger than the cap" do
    let(:limits) { { diff_limit: file_diff("lib/a.rb").length + 10 } }

    it "keeps whole files, names the rest and says how to fetch them" do
      text = packet.call(plan)

      expect(text).to include("diff --git a/lib/a.rb", "was cut to fit", "- `lib/b.rb`", "Run `gh pr diff 12` for the rest")
      expect(text).not_to include("diff --git a/lib/b.rb")
    end
  end

  context "when one file alone is larger than the cap" do
    let(:limits) { { diff_limit: 150 } }
    let(:diff) { file_diff("lib/huge.rb", lines: 50) }

    it "cuts it at a line and lists it as not shown in full" do
      text = packet.call(plan)
      shown = text[%r{<diff pr="12">\n(.*?)\n</diff>}m, 1]

      expect(shown.length).to be <= 150
      expect(shown).to start_with("diff --git a/lib/huge.rb").and(end_with("+added line"))
      expect(text).to include("- `lib/huge.rb`")
    end
  end

  context "when a document is larger than the cap" do
    let(:limits) { { document_limit: 20 } }

    it "cuts it and sends the reviewer to the plan folder" do
      expect(packet.call(plan)).to include("`spec.md` was cut at 20 characters. Read the rest in the plan folder.")
    end
  end

  context "when gh cannot produce the diff" do
    before { allow(github).to receive(:diff).and_raise(OpenLanes::Error, "could not read the diff of #12: HTTP 502") }

    it "says so, and does not keep the packet, so the next reviewer's start asks again" do
      expect(packet.call(plan)).to include("could not fetch the diff of #12. Run `gh pr diff 12` yourself.")
      expect(Dir.exist?(packets) ? Dir.children(packets) : []).to be_empty

      allow(github).to receive(:diff).and_return(diff)
      expect(packet.call(plan)).to include("diff --git a/lib/a.rb")
    end
  end

  context "when the plan has no open pull request" do
    let(:prs) { nil }

    it "says there is no diff and asks gh nothing" do
      expect(packet.call(plan)).to include("lists no open pull request")
      expect(github).not_to have_received(:diff)
    end
  end
end
