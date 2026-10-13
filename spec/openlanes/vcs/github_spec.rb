# frozen_string_literal: true

# The one class in this library that shells out. Every other spec injects a
# double for it, so without these examples the `gh` contract — the flags, the
# JSON shape, and every way it can fail — is entirely unverified.
#
# TTY::Command is stubbed rather than run: the suite must never reach the
# network, and a test that needs a GitHub login is a test nobody can run.
RSpec.describe OpenLanes::Vcs::GitHub do
  subject(:github) { described_class.new(command:) }

  let(:command) { instance_double(TTY::Command) }
  let(:result) { instance_double(TTY::Command::Result, out: payload) }

  let(:payload) do
    JSON.generate([
                    {
                      "number"      => 92,
                      "title"       => "Send transactional mail through Resend",
                      "url"         => "https://github.com/example/repo/pull/92",
                      "headRefName" => "kig/018.01-resend",
                      "files"       => [{ "path" => ".plans/018.01-🟡--deploy/plan.md" }, { "path" => "rails/Gemfile" }]
                    }
                  ])
  end

  before { allow(command).to receive(:run).and_return(result) }

  describe "#pulls" do
    it "asks gh for exactly the fields the resync needs" do
      github.pulls

      expect(command).to have_received(:run).with(
        "gh",
        "pr",
        "list",
        "--state",
        "all",
        "--limit",
        "200",
        "--json",
        "number,title,url,headRefName,files,state,isDraft,mergedAt"
      )
    end

    it "passes the requested state through" do
      github.pulls(state: "open")

      expect(command).to have_received(:run).with(
        "gh", "pr", "list", "--state", "open", anything, anything, anything, anything
      )
    end

    it "normalises headRefName to :branch and flattens files to paths" do
      expect(github.pulls.first).to eq(
        number: 92,
        title:  "Send transactional mail through Resend",
        url:    "https://github.com/example/repo/pull/92",
        branch: "kig/018.01-resend",
        files:  [".plans/018.01-🟡--deploy/plan.md", "rails/Gemfile"],
        state:  "Unknown",
        open:   false
      )
    end

    context "when a pull request has no files attached" do
      let(:payload) { JSON.generate([{ "number" => 1, "title" => "x", "headRefName" => "b" }]) }

      it "yields an empty list rather than nil, so callers need no guard" do
        expect(github.pulls.first[:files]).to eq([])
      end
    end

    context "when the repository genuinely has no pull requests" do
      let(:payload) { "[]" }

      it "returns nothing and does not treat it as an error" do
        expect(github.pulls).to eq([])
      end
    end

    # The failure this project actually hit: an invalid GH_TOKEN shadowing a
    # working keyring login makes gh exit 0 having printed nothing at all.
    context "when gh exits cleanly but prints nothing" do
      let(:payload) { "   \n" }

      it "blames authentication rather than reporting a parse error" do
        expect { github.pulls }.to raise_error(OpenLanes::Error, /authentication/i)
      end

      it "names the specific trap, so the reader looks in the right place" do
        expect { github.pulls }.to raise_error(OpenLanes::Error, /GH_TOKEN/)
      end
    end

    context "when gh returns something that is not JSON" do
      let(:payload) { "not json at all" }

      it "fails with a message that says gh was the source" do
        expect { github.pulls }.to raise_error(OpenLanes::Error, /could not list pull requests/)
      end
    end

    context "when gh exits non-zero" do
      before do
        allow(command).to receive(:run)
          .and_raise(TTY::Command::ExitError.new("gh pr list",
            instance_double(TTY::Command::Result,
              exit_status: 1,
              out:         "",
              err:         "could not determine base repository")))
      end

      it "surfaces gh's own complaint instead of a stack trace" do
        expect { github.pulls }.to raise_error(OpenLanes::Error, /could not list pull requests/)
      end
    end
  end

  describe "#retitle" do
    it "edits exactly the pull request it was given" do
      github.retitle(number: 92, title: "[018.01] Send transactional mail through Resend")

      expect(command).to have_received(:run).with(
        "gh", "pr", "edit", "92", "--title", "[018.01] Send transactional mail through Resend"
      )
    end

    context "when the edit is refused" do
      before do
        allow(command).to receive(:run)
          .and_raise(TTY::Command::ExitError.new("gh pr edit",
            instance_double(TTY::Command::Result,
              exit_status: 1,
              out:         "",
              err:         "pull request is closed")))
      end

      it "names the pull request that could not be changed" do
        expect { github.retitle(number: 92, title: "x") }.to raise_error(OpenLanes::Error, /could not retitle #92/)
      end
    end
  end

  describe "#available?" do
    it "reports whether gh is installed and authenticated" do
      allow(command).to receive(:run!).with("gh", "auth", "status")
                                      .and_return(instance_double(TTY::Command::Result, success?: true))

      expect(github).to be_available
    end
  end

  describe ".parse_refs" do
    it "takes numbers, #numbers and URLs in one list" do
      expect(described_class.parse_refs("12, #15, https://github.com/o/r/pull/18")).to eq(["12", "#15", "https://github.com/o/r/pull/18"])
    end

    it "drops a repeated reference rather than fetching it twice" do
      expect(described_class.parse_refs("12,12,15")).to eq(["12", "15"])
    end

    # Locally, in a hundredth of a second, naming the offending token — rather
    # than after four network round trips with a `gh` diagnostic attached.
    it "names what it could not read" do
      expect { described_class.parse_refs("12, banana, 15") }.to raise_error(OpenLanes::Error, /not a pull request number or URL: banana/)
    end

    it "refuses an empty list" do
      expect { described_class.parse_refs(" , ") }.to raise_error(OpenLanes::Error, /no pull requests/)
    end
  end

  describe ".state_label" do
    it "translates gh's enums into the words the state machine parses" do
      aggregate_failures do
        expect(described_class.state_label({ "mergedAt" => "2026-01-01", "state" => "MERGED" })).to eq("Merged 🟣")
        expect(described_class.state_label({ "state" => "OPEN", "isDraft" => true })).to eq("WIP 🟡")
        expect(described_class.state_label({ "state" => "OPEN" })).to eq("Open 🟡")
        expect(described_class.state_label({ "state" => "CLOSED" })).to eq("Closed 🔴")
      end
    end

    # A closed-unmerged pull request is finished business; a merged one is not
    # the same thing, and the folder's invariants turn on the difference.
    it "does not call a closed pull request merged" do
      expect(described_class.state_label({ "state" => "CLOSED", "mergedAt" => nil })).to eq("Closed 🔴")
    end
  end

  describe "#pull_request" do
    let(:payload) do
      { number: 12, title: "Add health checks", url: "https://github.com/o/r/pull/12",
       state: "MERGED", isDraft: false, mergedAt: "2026-08-01T10:00:00Z",
       body: "Adds /healthz." }.to_json
    end

    it "reads one pull request by number or URL" do
      command = instance_double(TTY::Command)
      allow(command).to receive(:run).and_return(instance_double(TTY::Command::Result, out: payload))

      expect(described_class.new(command:).pull_request("12")).to include(number: 12, state: "Merged 🟣", body: "Adds /healthz.")
    end

    it "blames authentication rather than reporting a parse error when gh says nothing" do
      command = instance_double(TTY::Command)
      allow(command).to receive(:run).and_return(instance_double(TTY::Command::Result, out: ""))

      expect { described_class.new(command:).pull_request("12") }.to raise_error(OpenLanes::Error, /gh auth status/)
    end

    it "names the pull request it could not read when gh exits non-zero" do
      command = instance_double(TTY::Command)
      allow(command).to receive(:run)
        .and_raise(TTY::Command::ExitError.new("gh pr view",
          instance_double(TTY::Command::Result,
            exit_status: 1,
            out:         "",
            err:         "no pull requests found for branch")))

      expect { described_class.new(command:).pull_request("12") }.to raise_error(OpenLanes::Error, /could not read pull request 12/)
    end

    it "wraps garbage output the same way, so the caller sees one error shape" do
      command = instance_double(TTY::Command)
      allow(command).to receive(:run).and_return(instance_double(TTY::Command::Result, out: "not json"))

      expect { described_class.new(command:).pull_request("12") }.to raise_error(OpenLanes::Error, /could not read pull request 12/)
    end
  end

  describe "#pull_requests" do
    let(:payload) do
      { number: 12, title: "Add health checks", url: "https://github.com/o/r/pull/12",
       state: "OPEN", isDraft: false, mergedAt: nil, body: "Adds /healthz." }.to_json
    end

    # `--prs 12,15` fetches each in turn; the order given is the order the
    # roll-up is written in, so it must survive the fetch.
    it "fetches each reference and keeps the order asked for" do
      results = github.pull_requests(["12", "#15"])

      aggregate_failures do
        expect(results.size).to eq(2)
        expect(command).to have_received(:run).with("gh", "pr", "view", "12", anything, anything)
        expect(command).to have_received(:run).with("gh", "pr", "view", "#15", anything, anything)
      end
    end

    it "returns the same normalised hashes as a single fetch would" do
      expect(github.pull_requests(["12"]).first).to include(number: 12, state: "Open 🟡")
    end
  end
end
