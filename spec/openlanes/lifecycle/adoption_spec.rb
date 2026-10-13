# frozen_string_literal: true

# Pull requests that resolve to no plan get one minted for them. The property
# that matters is not that the numbering is *deterministic* — the obvious
# parallel design is deterministic and still wrong — but that it is
# **distinct**, which is why the allocation is a serial pass.
RSpec.describe OpenLanes::Lifecycle::Adoption, :tree do
  subject(:adoption) { described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), github:, root: plans_root) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }

  let!(:tree) do
    plans do |t|
      t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body }
      t.plan "024.00", :approved, "engine-core", prs: [t.merged(2, "Ship it")]
    end
  end

  def pull(number, title, branch: "kig/work-#{number}", files: [])
    { number:, title:, branch:, files:, state: "Open 🟡", open: true,
     url: "https://github.com/example/repo/pull/#{number}" }
  end

  before do
    allow(github).to receive(:pull_request) { |ref|
      { number: ref.to_i, title: "PR #{ref}", url: "https://github.com/example/repo/pull/#{ref}",
       state: "Open 🟡", body: "What #{ref} did." }
    }
  end

  describe "#plan" do
    # THE case. Fifteen branches cut from the same main all see 024.00 as the
    # furthest plan. "Read the highest and add .01" gives all fifteen 024.01.
    # Allocating serially gives them .01 through .15.
    context "when many pull requests all see the same furthest plan" do
      let(:pulls) { (95..109).map { |n| pull(n, "Work #{n}") } }

      it "gives every one of them a different number" do
        numbers = adoption.plan(pulls).map { |a| a.ordinal.to_s }

        expect(numbers.uniq.size).to eq(15)
      end

      it "numbers them in ascending pull request order, so the run is reproducible" do
        adoptees = adoption.plan(pulls)

        aggregate_failures do
          expect(adoptees.map { |a| a.pull[:number] }).to eq((95..109).to_a)
          expect(adoptees.first.ordinal.to_s).to eq("024.01")
          expect(adoptees.last.ordinal.to_s).to eq("024.15")
        end
      end
    end

    it "steps over minors the tree already holds rather than colliding with them" do
      plans { |t| t.plan "024.01", :approved, "already-here", prs: [t.merged(9, "x")] }
      fresh = described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), github:, root: plans_root)

      expect(fresh.plan([pull(95, "Work")]).first.ordinal.to_s).to eq("024.02")
    end

    # Branches are not all rebased onto the same main, and the number should
    # follow where the work actually started.
    it "uses what the pull request touched when its branch cannot be read" do
      touching = pull(95, "Sweeping", files: [".plans/001.00-⚪️ → initial-spec/spec.md"])

      expect(adoption.plan([touching]).first.ordinal.to_s).to eq("001.01")
    end

    it "names the folder from the pull request's title, prefix stripped" do
      expect(adoption.plan([pull(95, "[dev] Add the health checks")]).first.dirname).to eq("024.01-🕰️ → add-the-health-checks")
    end

    it "refuses to run past the last retroactive slot rather than wrapping" do
      crowded = plans { |t| (1..99).each { |m| t.plan(format("024.%02d", m), :new, "p#{m}", files: { "spec.md" => spec_body }) } }
      fresh = described_class.new(tree: OpenLanes::Plans::Tree.new(dir: crowded), github:, root: crowded)

      expect(fresh.plan([pull(95, "One too many")])).to be_empty
    end
  end

  describe "#call" do
    let(:pulls) { [pull(95, "Health checks"), pull(96, "Structured logging")] }

    it "creates a folder for each, holding the pull request that earned it" do
      adoption.call(pulls)

      aggregate_failures do
        expect(Dir.children(plans_root)).to include("024.01-🕰️ → health-checks", "024.02-🕰️ → structured-logging")
        expect(File.read(File.join(plans_root, "024.01-🕰️ → health-checks", "pull-requests.md"))).to include("/pull/95", "What 95 did.")
      end
    end

    # 🕰️ Retroactive means "live, but neither specified nor planned", and its
    # invariant demands recorded pull requests and no spec.md.
    it "produces folders whose contents justify the state they claim" do
      adoption.call(pulls)
      subjects = OpenLanes::Plans::Tree.new(dir: plans_root).reload.subjects
                                       .select { |s| s.status.key == :retroactive }

      expect(subjects.map(&:violation).compact).to be_empty
    end

    it "leaves spec.md to the writer" do
      adoption.call(pulls)

      expect(Dir.children(File.join(plans_root, "024.01-🕰️ → health-checks"))).to eq(["pull-requests.md"])
    end
  end
end
