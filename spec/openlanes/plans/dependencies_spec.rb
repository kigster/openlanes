# frozen_string_literal: true

# Only `depends_on:` is ever written; who a plan blocks is derived, so the
# blocking plan's own spec.md must never change for it (N6).
RSpec.describe OpenLanes::Plans::Dependencies, :tree do
  subject(:deps) { tree.dependencies }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  def spec_path(ordinal) = File.join(tree.find(ordinal).feature.path, "spec.md")

  context "when 050 depends on an open 034" do
    before do
      plans do |t|
        t.plan "034.00", :planned, "parser", files: { "spec.md" => spec_body }
        t.plan "050.00", :planned, "printer", files: { "spec.md" => needs("034.00") }
        t.plan "060.00", :planned, "unchecked", files: { "spec.md" => spec_body }
      end
    end

    it "derives blocks_of without writing to the blocking plan" do
      before = File.binread(spec_path("034.00"))

      expect(tree.blocks_of("034.00")).to eq(["050.00"])
      expect(File.binread(spec_path("034.00"))).to eq(before)
    end

    it "keeps 050 waiting on 034 and gives the reason" do
      expect(deps.waiting_on("050.00")).to eq(["034.00"])
      expect(deps.reason("050.00")).to eq("waiting on 034.00")
      expect(deps.reason("034.00")).to be_nil
    end

    it "tells an absent key from a declared one" do
      expect(deps.depends_on("060.00")).to be_nil
      expect(deps.depends_on("050.00")).to eq(["034.00"])
      expect(deps.blocks_of("060.00")).to eq([])
    end

    it "is dropped by Tree#reload" do
      first = tree.dependencies
      expect(tree.reload.dependencies).not_to equal(first)
    end
  end

  # A shipped plan moves into archive/. Read from the top level only, the
  # prerequisite vanished the moment it was done, and 050 was held forever
  # as waiting on it.
  context "when the prerequisite has shipped and sits in archive/" do
    before do
      plans do |t|
        t.plan "034.00",
          :approved,
          "parser",
          files:       { "spec.md" => spec_body },
          prs:         [t.merged(1, "Ship")],
          under:       "archive",
          archived_on: Date.new(2026, 10, 1)
        t.plan "050.00", :planned, "printer", files: { "spec.md" => needs("034.00") }
      end
    end

    it "does not hold the dependent" do
      aggregate_failures do
        expect(tree.find("034.00")).to be_nil
        expect(deps.unknown("050.00")).to be_empty
        expect(deps.waiting_on("050.00")).to be_empty
        expect(deps.closed("050.00")).to eq(["034.00"])
        expect(deps.reason("050.00")).to be_nil
      end
    end

    it "still names the archived plan's dependents" do
      expect(tree.blocks_of("034.00")).to eq(["050.00"])
    end
  end

  context "when an archived plan itself declared a dependency" do
    before do
      plans do |t|
        t.plan "010.00",
          :approved,
          "base",
          files:       { "spec.md" => spec_body },
          prs:         [t.merged(1, "Base")],
          under:       "archive",
          archived_on: Date.new(2026, 9, 1)
        t.plan "020.00",
          :approved,
          "top",
          files:       { "spec.md" => needs("010.00") },
          prs:         [t.merged(2, "Top")],
          under:       "archive",
          archived_on: Date.new(2026, 9, 2)
      end
    end

    it "answers blocks_of for the archived plan" do
      aggregate_failures do
        expect(tree.blocks_of("010.00")).to eq(["020.00"])
        expect(deps.depends_on("020.00")).to eq(["010.00"])
      end
    end
  end

  context "with a done, a blocked and an unknown dependency" do
    before do
      plans do |t|
        t.plan "010.00", :approved, "shipped", files: { "spec.md" => spec_body }, prs: [t.merged(1, "Ship")]
        t.plan "020.00", :product_blocked, "stuck", files: { "blocked.md" => "## B1 Which?\n" }
        t.plan "030.00", :planned, "waits", files: { "spec.md" => needs("010.00", "020.00", "099.00") }
      end
    end

    it "ignores the done one and waits on the blocked and unknown ones" do
      expect(deps.waiting_on("030.00")).to eq(%w[020.00 099.00])
      expect(deps.closed("030.00")).to eq(["010.00"])
      expect(deps.unknown("030.00")).to eq(["099.00"])
    end

    # "waiting on 099.00" read like a wait that would end; a typo never does.
    it "names the unknown one apart from the real wait" do
      expect(deps.reason("030.00")).to eq("unknown plan 099.00; waiting on 020.00")
    end
  end

  context "with a two-plan cycle" do
    before do
      plans do |t|
        t.plan "034.00", :planned, "a", files: { "spec.md" => needs("050.00") }
        t.plan "050.00", :planned, "b", files: { "spec.md" => needs("034.00") }
      end
    end

    it "reports the cycle from each side, starting at the asked plan" do
      expect(deps.cycles).to eq([%w[034.00 050.00 034.00]])
      expect(deps.cycle_of("050.00")).to eq(%w[050.00 034.00 050.00])
      expect(deps.reason("034.00")).to eq("cycle: 034.00 → 050.00 → 034.00")
    end
  end

  context "with a three-plan cycle and a plan hanging off it" do
    before do
      plans do |t|
        t.plan "001.00", :planned, "a", files: { "spec.md" => needs("002.00") }
        t.plan "002.00", :planned, "b", files: { "spec.md" => needs("003.00") }
        t.plan "003.00", :planned, "c", files: { "spec.md" => needs("001.00") }
        t.plan "004.00", :planned, "d", files: { "spec.md" => needs("001.00") }
      end
    end

    it "finds the ring once and leaves the plan off it out" do
      expect(deps.cycles).to eq([%w[001.00 002.00 003.00 001.00]])
      expect(deps.cycle_of("002.00")).to eq(%w[002.00 003.00 001.00 002.00])
      expect(deps.cycle_of("004.00")).to be_nil
      expect(deps.reason("004.00")).to eq("waiting on 001.00")
    end
  end

  # 034 shipped while it still named 050, and 050 still names 034. The
  # dependency on a done plan is met, so there is no deadlock to report.
  context "when one side of a former cycle is done" do
    before do
      plans do |t|
        t.plan "034.00", :approved, "a", files: { "spec.md" => needs("050.00") }, prs: [t.merged(34, "Ship")]
        t.plan "050.00", :planned, "b", files: { "spec.md" => needs("034.00") }
      end
    end

    it "lets the open side start" do
      expect(deps.cycles).to be_empty
      expect(deps.reason("050.00")).to be_nil
    end
  end

  context "with a plan that names itself" do
    before { plans { |t| t.plan "007.00", :planned, "self", files: { "spec.md" => needs("007.00") } } }

    it "reports a one-plan cycle" do
      expect(deps.cycle_of("007.00")).to eq(%w[007.00 007.00])
    end
  end

  # Enumerating every path visited each plan once per path to it, which is
  # exponential here: 28 plans took 2.6 seconds.
  context "with a long chain where each plan waits on the two before it" do
    before do
      plans do |t|
        (1..40).each do |i|
          before = [i - 1, i - 2].select(&:positive?).map { format("%03d.00", it) }
          t.plan format("%03d.00", i), :planned, "p#{i}", files: { "spec.md" => needs(*before) }
        end
      end
    end

    it "visits each plan once" do
      graph = described_class.new(tree)
      visits = Hash.new(0)
      allow(graph).to(receive(:waiting_on).and_wrap_original { |m, o| visits[o.to_s] += 1 and m.call(o) })

      expect(graph.cycles).to be_empty
      expect(visits.values.max).to eq(1)
      expect(graph.reason("040.00")).to eq("waiting on 038.00, 039.00")
    end
  end

  # A recursive walk recursed once per plan in a chain, so a long enough
  # chain raised SystemStackError inside the dispatcher tick.
  context "with a chain far deeper than the Ruby stack" do
    before { plans { |t| t.plan "001.00", :planned, "only" } }

    it "finds every component without recursing" do
      graph = described_class.new(tree)
      chain = (0...50_000).to_h { |i| [format("%06d", i), i.zero? ? [] : [format("%06d", i - 1)]] }
      chain["000000"] = ["049999"]
      allow(graph).to receive(:open_edges).and_return(chain)

      expect(graph.send(:components).map(&:size)).to eq([50_000])
    end
  end
end
