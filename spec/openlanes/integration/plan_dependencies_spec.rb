# frozen_string_literal: true

require "open3"

# Plan 008.00 end to end: a real `.plans` tree, the real executable, nothing
# stubbed. `depends_on:` is read from spec.md, the reverse edge reaches
# `list-plans`, and `run --dry-run` holds the waiting plan and says why.
RSpec.describe "plan dependencies, through the executable", :tree do
  let(:exe) { File.expand_path("../../../exe/openlanes", __dir__) }
  let(:project) { File.dirname(plans_root) }

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  def ready(spec) = { "spec.md" => spec, "plan.md" => "# P", "plan-frontend.md" => "## F1" }

  # @return [Array(String, Integer)] STDOUT and STDERR together, and the exit status
  def openlanes(*)
    out, status = Open3.capture2e({ "NO_COLOR" => "1" }, exe, *, "--dir", plans_root, chdir: project)
    [strip_ansi(out), status.exitstatus]
  end

  def spec_of(ordinal) = File.join(OpenLanes::Plans::Tree.new(dir: plans_root).find(ordinal).feature.path, "spec.md")

  before { system("git", "init", "-q", project, exception: true) }

  context "when 050 depends on an open 034" do
    before do
      plans do |t|
        t.plan "034.00", :planned, "parser", files: ready(spec_body(title: "Parser"))
        t.plan "050.00", :planned, "printer", files: ready(needs("034.00"))
      end
    end

    it "lists 034 as blocking 050 and leaves 034's spec.md untouched" do
      before = File.binread(spec_of("034.00"))
      out, status = openlanes("list-plans")

      expect(status).to eq(0)
      expect(out.lines.grep(/034\.00/).first).to include("blocks 050.00")
      expect(File.binread(spec_of("034.00"))).to eq(before)
    end

    it "assigns 034 and not 050, and names 050 as waiting on 034.00" do
      out, = openlanes("run", "--dry-run", "--isolation", "shared")

      expect(out).to match(/034\.00\s.*would invoke/)
      expect(out).not_to match(/050\.00\s.*would invoke/)
      expect(out).to include('050.00 waiting on 034.00')
    end
  end

  context "when 034 and 050 depend on each other" do
    before do
      plans do |t|
        t.plan "034.00", :planned, "parser", files: ready(needs("050.00"))
        t.plan "050.00", :planned, "printer", files: ready(needs("034.00"))
      end
    end

    it "assigns neither and gives a cycle as the reason for both" do
      out, = openlanes("run", "--dry-run", "--isolation", "shared")

      expect(out).not_to include("would invoke")
      expect(out).to include("034.00 cycle: 034.00 → 050.00 → 034.00",
        "050.00 cycle: 050.00 → 034.00 → 050.00")
    end
  end
end
