# frozen_string_literal: true

# `openlanes link` in-process: the real Linker over a real `.plans` tree, with
# the agent and git's mainline answer stubbed. link_spec.rb runs the binary
# against real git; these pin the reports, the exit statuses and the refusals,
# which a subprocess hides from the coverage gate.
RSpec.describe OpenLanes::CLI::Link, :tree do
  let(:outcome) { Data.define(:ok, :note) }

  let(:mainline) { instance_double(OpenLanes::Vcs::Mainline, warnings: [], mainline?: false, note: "", pull: true) }
  let(:agent) { ->(_agent, _subject, **) { outcome.new(ok: true, note: nil) } }

  before do
    allow(OpenLanes::Vcs).to receive(:mainline).and_return(mainline)
    allow(OpenLanes::Execution).to receive(:executor).and_return(->(*a, **k) { agent.call(*a, **k) })
  end

  def keyless(ordinal = "050.00", state = :ready_for_linking)
    plans { |t| t.plan ordinal, state, "parser-consumer", files: { "spec.md" => "---\nlane: full\n---\n# Parser Consumer\n", "plan.md" => "" } }
  end

  def spec_of(ordinal) = File.read(File.join(Dir.glob(File.join(plans_root, "#{ordinal}*")).first, "spec.md"))

  def write_key(subject) = File.write(File.join(subject.feature.path, "spec.md"), "---\nlane: full\ndepends_on: [none]\n---\n# Linked\n")

  def invoke(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      described_class.new.call(dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    { out: strip_ansi(out.string), err: strip_ansi(err.string), status: }
  end

  context "with --dry-run" do
    it "names the agent it would invoke for each keyless plan" do
      keyless
      expect(invoke(dry_run: true)).to include(out: "would invoke ewoki-linker for 050.00\n", status: 0)
    end

    it "says so when no plan is waiting" do
      plans
      expect(invoke(dry_run: true)).to include(out: "No plan is waiting for a link.\n", status: 0)
    end

    it "never pulls, even on the mainline" do
      allow(mainline).to receive(:mainline?).and_return(true)
      keyless
      invoke(dry_run: true)

      expect(mainline).not_to have_received(:pull)
    end
  end

  it "reports a plan the agent linked, and moves it on from 🔗" do
    keyless
    allow(agent).to receive(:call) do |_, subject, **|
      write_key(subject)
      outcome.new(ok: true, note: nil)
    end

    result = invoke

    aggregate_failures do
      expect(result).to include(status: 0)
      expect(result[:out]).to eq("1 plan linked: 050.00.\nTheir spec.md files changed; commit the current branch to persist.\n")
      expect(Dir.children(plans_root).first).to include("📋")
      expect(spec_of("050.00")).to include("depends_on: [none]")
    end
  end

  it "says nothing new was found, and fails the plan, when the agent wrote no key" do
    keyless
    expect(invoke).to include(out: "No new dependencies found.\nfailed 050.00: ran, but spec.md still does not answer depends_on:\n",
      status: 1)
  end

  it "exits 0 with nothing found when no plan needs a link" do
    expect(invoke).to include(out: "No new dependencies found.\n", status: 0)
  end

  it "lists a failed plan with its note and exits 1" do
    keyless
    allow(agent).to receive(:call).and_return(outcome.new(ok: false, note: "agent timed out"))

    expect(invoke).to include(out: "No new dependencies found.\nfailed 050.00: agent timed out\n", status: 1)
  end

  it "passes git's warnings on, and goes on" do
    allow(mainline).to receive(:warnings).and_return(["on branch feature, not main"])
    keyless

    expect(invoke(dry_run: true)).to include(err: a_string_including("on branch feature, not main"), status: 0)
  end

  it "refuses when the mainline cannot be pulled" do
    allow(mainline).to receive_messages(mainline?: true, pull: false, note: "git pull failed")
    keyless

    expect(invoke).to include(err: a_string_including("git pull failed"), status: 69)
  end

  it "reports a dependency cycle and exits 1" do
    plans do |t|
      t.plan "060.00", :ready_for_planning, "left", files: { "spec.md" => "---\nlane: full\ndepends_on: [\"061.00\"]\n---\n# Left\n" }
      t.plan "061.00", :ready_for_planning, "right", files: { "spec.md" => "---\nlane: full\ndepends_on: [\"060.00\"]\n---\n# Right\n" }
    end

    expect(invoke).to include(err: a_string_including("dependency cycle"), status: 1)
  end

  it "refuses with the library's message when linking cannot start" do
    keyless
    allow(OpenLanes::Lifecycle).to receive(:link).and_raise(OpenLanes::Error, "no agent handles 🔗")

    expect(invoke).to include(err: a_string_including("no agent handles 🔗"), status: 65)
  end
end
