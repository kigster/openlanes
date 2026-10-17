# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Setup do
  subject(:command) { described_class.new }

  let(:checks) { %w[brew Brewfile claude gh redis].map { pass(it) } }
  let(:missing) { [] }
  let(:machine) do
    instance_double(OpenLanes::Setup::Machine, bundle_command: %w[brew bundle --no-upgrade --file /gem/Brewfile])
  end

  def pass(name) = OpenLanes::Setup::Check.new(name:, ok: true, detail: "fine", fix: nil)

  before do
    allow(OpenLanes::Setup).to receive(:machine).and_return(machine)
    allow(machine).to receive(:call) do |dry_run:|
      OpenLanes::Setup::Machine::Outcome.new(missing:, installed: !dry_run && !missing.empty?, checks:)
    end
  end

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dry_run: false, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  it "needs no project" do
    expect(described_class).to be_standalone
  end

  it "is registered as openlanes setup" do
    expect(OpenLanes::CLI.get(["setup"]).command).to eq(described_class)
  end

  context "with a ready machine" do
    it "prints ✓ for every check and exits 0" do
      out, _err, status = run
      expect(out.lines.map { it[0] }).to eq(["✓"] * 5)
      expect(status).to eq(0)
    end
  end

  context "with gh logged out" do
    let(:checks) do
      [pass("brew"), OpenLanes::Setup::Check.new(name: "gh", ok: false, detail: "gh is not logged in", fix: "gh auth login")]
    end

    it "prints ✗ with the fix and exits non-zero" do
      out, err, status = run
      expect(out).to include("✗ gh    gh is not logged in\n    fix: gh auth login")
      expect(err).to include("not ready")
      expect(status).to eq(69)
    end
  end

  context "with -n" do
    let(:missing) { %w[vips jq] }

    it "installs nothing and lists what it would do" do
      out, err, = run(dry_run: true)
      expect(machine).to have_received(:call).with(dry_run: true)
      expect(err).to include("nothing was installed",
        "Would install: vips, jq",
        "Would run: brew bundle --no-upgrade --file /gem/Brewfile",
        "Checks: brew, Brewfile, claude, gh, redis")
      expect(out.lines.size).to eq(5)
    end

    context "when nothing is missing" do
      let(:missing) { [] }

      it "says it would install nothing" do
        _out, err, = run(dry_run: true)
        expect(err).to include("Would install: nothing")
        expect(err).not_to include("Would run")
      end
    end
  end

  it "builds the machine with the Redis it was given" do
    run(redis_url: "redis://elsewhere:6379/0")
    expect(OpenLanes::Setup).to have_received(:machine).with(redis_url: "redis://elsewhere:6379/0")
  end

  describe "OpenLanes::Setup.render" do
    it "paints the marks when colour is on" do
      allow(OpenLanes::UI).to receive(:color?).and_return(true)
      expect(OpenLanes::Setup.render([pass("gh")])).to include("\e[")
    end

    it "prints no fix line for a ✗ that has none" do
      check = OpenLanes::Setup::Check.new(name: "x", ok: false, detail: "broken", fix: nil)
      expect(strip_ansi(OpenLanes::Setup.render([check]))).to eq("✗ x  broken\n")
    end
  end
end
