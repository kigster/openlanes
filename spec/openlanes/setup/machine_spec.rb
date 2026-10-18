# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::Machine do
  subject(:machine) do
    described_class.new(brewfile: "/gem/Brewfile", redis_url:, capture:, install:, which:, ping:)
  end

  let(:redis_url) { "redis://localhost:6379/0" }
  let(:on_path) { %w[brew claude gh] }
  let(:bundled) { true }
  let(:logged_in) { true }
  let(:answers) { true }
  let(:installs) { [] }
  let(:which) { ->(name) { on_path.include?(name) } }
  let(:ping) { ->(_url) { answers } }
  let(:install) { ->(argv) { (installs << argv) && true } }
  let(:capture) do
    lambda do |argv, _env|
      case argv.first(2)
      when %w[brew bundle]
        bundled ? ["The Brewfile's dependencies are satisfied.\n", true] : ["→ Formula vips needs to be installed or updated.\n→ Formula jq needs to be installed or updated.\n", false]
      when %w[gh auth] then ["", logged_in]
      else raise "unexpected #{argv}"
      end
    end
  end

  def check(name) = machine.checks.find { it.name == name }

  context "with a machine that has everything" do
    it "passes every check" do
      expect(machine.checks).to all(be_ok)
      expect(machine).to be_ready
    end

    it "installs nothing" do
      outcome = machine.call
      expect(installs).to be_empty
      expect(outcome).to have_attributes(missing: [], installed: false, ok?: true)
    end
  end

  context "when the Brewfile lacks something" do
    let(:bundled) { false }

    it "names what is missing" do
      expect(machine.missing).to eq(%w[vips jq])
      expect(check("Brewfile")).to have_attributes(ok?: false,
        detail: "missing: vips, jq",
        fix: "brew bundle --no-upgrade --file /gem/Brewfile")
    end

    it "runs brew bundle --no-upgrade on the gem's Brewfile" do
      outcome = machine.call
      expect(installs).to eq([%w[brew bundle --no-upgrade --file /gem/Brewfile]])
      expect(outcome).to have_attributes(missing: %w[vips jq], installed: true)
    end

    it "installs nothing on a dry run" do
      outcome = machine.call(dry_run: true)
      expect(installs).to be_empty
      expect(outcome.missing).to eq(%w[vips jq])
    end
  end

  context "when brew bundle check fails without naming anything" do
    let(:capture) { ->(argv, _env) { argv.first == "brew" ? ["Error: no tap\n", false] : ["", true] } }

    it "points at brew bundle check" do
      expect(check("Brewfile").detail).to eq("missing: see brew bundle check")
    end
  end

  context "without Homebrew" do
    let(:on_path) { %w[claude gh] }

    it "fails brew and the Brewfile, with the installer as the fix" do
      expect(check("brew")).to have_attributes(ok?: false, fix: described_class::HOMEBREW_INSTALL)
      expect(check("Brewfile")).to have_attributes(ok?: false, detail: "needs Homebrew")
    end

    it "installs nothing and reports nothing missing" do
      expect(machine.call).to have_attributes(missing: [], installed: false, ok?: false)
      expect(installs).to be_empty
    end
  end

  context "without the claude CLI" do
    let(:on_path) { %w[brew gh] }

    it "gives the installer as the fix" do
      expect(check("claude")).to have_attributes(ok?: false, fix: described_class::CLAUDE_INSTALL)
    end
  end

  context "with gh logged out" do
    let(:logged_in) { false }

    it "fails gh with gh auth login as the fix" do
      expect(check("gh")).to have_attributes(ok?: false, detail: "gh is not logged in", fix: "gh auth login")
      expect(machine).not_to be_ready
    end
  end

  context "without gh" do
    let(:on_path) { %w[brew claude] }

    it "installs it and logs in" do
      expect(check("gh").fix).to eq("brew install gh && gh auth login")
    end
  end

  context "when Redis does not answer" do
    let(:answers) { false }

    it "starts a local Redis" do
      expect(check("redis")).to have_attributes(ok?: false, fix: "brew services start redis")
    end

    context "when it is another machine's" do
      let(:redis_url) { "redis://kig:secret@10.0.4.2:6379/0" }

      it "masks the password and says where to set the URL" do
        expect(check("redis").detail).to eq("redis://kig:***@10.0.4.2:6379/0 does not answer")
        expect(check("redis").fix).to include(".openlanes.yml")
      end
    end
  end

  describe "#redis_url" do
    let(:redis_url) { nil }

    it "follows W16's order when none is given" do
      allow(OpenLanes::Live).to receive(:redis_url).and_return("redis://elsewhere:6379/0")
      expect(machine.redis_url).to eq("redis://elsewhere:6379/0")
    end

    it "uses no settings when the project's file cannot be read" do
      allow(OpenLanes::Config).to receive(:current).and_raise(OpenLanes::Error, "bad file")
      expect(machine.redis_url).to eq(OpenLanes::Live.redis_url(config: OpenLanes::Config.new))
    end
  end

  describe "the default seams" do
    let(:real) { described_class.new }

    it "captures a command's output and status" do
      expect(real.send(:capture, ["ruby", "-e", "print :hi"], {})).to eq(["hi", true])
    end

    it "treats a command that is not there as a failure" do
      expect(real.send(:capture, ["openlanes-no-such-command"], {})).to eq(["", false])
    end

    it "installs through system, with brew's output on STDERR" do
      allow(real).to receive(:system).and_return(true)
      expect(real.send(:install, %w[brew bundle])).to be(true)
      expect(real).to have_received(:system).with("brew", "bundle", out: $stderr, err: $stderr)
    end

    it "finds a command on PATH" do
      expect(real.send(:on_path?, "ruby")).to be(true)
      expect(real.send(:on_path?, "openlanes-no-such-command")).to be(false)
    end

    it "pings Redis, and answers false when it is not there" do
      allow(OpenLanes::Live).to receive(:connect).with("redis://up").and_return(:store)
      allow(OpenLanes::Live).to receive(:connect).with("redis://down").and_raise(OpenLanes::Live::Unavailable)
      expect(real.send(:ping?, "redis://up")).to be(true)
      expect(real.send(:ping?, "redis://down")).to be(false)
    end
  end
end
