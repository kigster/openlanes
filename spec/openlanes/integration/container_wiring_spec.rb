# frozen_string_literal: true

# Two real command paths, end to end, with one thing swapped: the `github`
# key in the container, for a fake that records what it was asked. The fake
# receiving the calls proves the key is what the commands reach for, and
# STDOUT matching a golden captured before the wiring proves the wiring
# changed nothing a user can see (A9).
#
# The goldens under `spec/fixtures/golden/container_wiring/` were written
# from `main` at `bca5b1b0`, before any class asked the container for a
# collaborator. To capture them again from a checkout of that commit:
#
#   OPENLANES_GOLDEN=write bundle exec rspec spec/openlanes/integration/container_wiring_spec.rb
#
# In that mode the fake is also handed out by `Vcs::GitHub.new`, because on
# `main` nothing asked the container for it yet.
RSpec.describe "the container through two real commands", :tree do
  # The GitHub seam, remembering every call. Only `pulls` is answered: a dry
  # run retitles nothing, so anything else asked of it is a wiring bug worth
  # a NoMethodError.
  let(:recording_github) do
    Class.new do
      attr_reader :calls

      def initialize(pulls)
        @pulls = pulls
        @calls = []
      end

      def pulls(*args, **kwargs)
        @calls << [:pulls, args, kwargs]
        @pulls
      end
    end
  end

  let(:golden_dir) { File.expand_path("../../fixtures/golden/container_wiring", __dir__) }

  let(:github) do
    recording_github.new([
                           { number: 7, title: "Add the DSL", url: "https://github.com/example/repo/pull/7",
                             branch: "kig/001.00-tax-rule-dsl", files: [], state: "Open 🟡", open: true },
                           { number: 9, title: "Bump CI cache", url: "https://github.com/example/repo/pull/9",
                             branch: "", files: [], state: "Open 🟡", open: true }
                         ])
  end

  before do
    plans { |t| t.plan("001.00", :new, "tax-rule-dsl", files: { "spec.md" => "# Tax Rule DSL\n\nA language for the rules.\n" }) }
    OpenLanes::Container.stub("github", github)
    allow(OpenLanes::Vcs::GitHub).to receive(:new).and_return(github) if writing?
  end

  def writing? = ENV["OPENLANES_GOLDEN"] == "write"

  def stdout_of
    out = CapturedStream.new
    err = CapturedStream.new
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      yield
    ensure
      $stdout, $stderr = original_out, original_err
    end
    strip_ansi(out.string)
  end

  # @param name [String] the golden's file name, without extension
  # @param actual [String] what the command wrote to STDOUT
  def expect_golden(name, actual)
    path = File.join(golden_dir, "#{name}.txt")
    if writing?
      FileUtils.mkdir_p(golden_dir)
      File.write(path, actual)
    end

    expect(actual).to eq(File.read(path))
  end

  describe "resync prs --dry-run" do
    let(:stdout) do
      stdout_of { OpenLanes::CLI::Resync::Prs.new.call(dir: plans_root, dry_run: true, adopt: false) }
    end

    # Once for the stale titles and once for the candidates: both reads must
    # land on the one client the container handed out.
    it "reaches the container's GitHub client down the real call chain" do
      stdout

      expect(github.calls.map(&:first)).to eq(%i[pulls pulls])
    end

    it "prints exactly what main printed" do
      expect_golden("resync_prs", stdout)
    end
  end

  describe "agents list" do
    let(:stdout) { stdout_of { OpenLanes::CLI::Agents::List.new.call } }

    it "resolves every adapter from the container to probe it" do
      expect(stdout).to include("claude", "codex", "pi", "grok", "gemini")
    end

    it "prints exactly what main printed" do
      expect_golden("agents_list", stdout)
    end
  end
end
