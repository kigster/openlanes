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
        "number,title,url,headRefName,files,state,isDraft,mergedAt,labels"
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
        open:   false,
        labels: []
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

  # Copilot on #69: label sync ran gh in the engine's directory, which
  # --root can point away from.
  describe "chdir:" do
    it "runs every gh command in the checkout it names" do
      result = instance_double(TTY::Command::Result, out: "[]", success?: true)
      allow(command).to receive_messages(run: result, run!: result)
      rooted = described_class.new(command:, chdir: "/tmp/elsewhere")

      rooted.label_colours
      rooted.available?

      aggregate_failures do
        expect(command).to have_received(:run).with("gh", "label", "list", "--limit", "1000", "--json", "name,color", chdir: "/tmp/elsewhere")
        expect(command).to have_received(:run!).with("gh", "auth", "status", chdir: "/tmp/elsewhere")
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

  describe ".number_of" do
    it "reads a bare, a #-prefixed and a URL reference" do
      aggregate_failures do
        expect(described_class.number_of("12")).to eq(12)
        expect(described_class.number_of(12)).to eq(12)
        expect(described_class.number_of("#12")).to eq(12)
        expect(described_class.number_of("https://github.com/o/r/pull/7/")).to eq(7)
        expect(described_class.number_of("https://github.com/o/r/pull/7/files")).to eq(7)
        expect(described_class.number_of("https://github.com/o/r/pull/7#issuecomment-1234")).to eq(7)
      end
    end

    it "refuses anything else rather than guessing from trailing digits" do
      %w[https://github.com/o/r/issues/1234 pr-12 nope].each do |ref|
        expect { described_class.number_of(ref) }.to raise_error(OpenLanes::Error, /not a pull request number or URL: #{ref}/)
      end
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
       body: "Adds /healthz.", labels: [{ name: "ready-to-merge" }] }.to_json
    end

    it "reads one pull request by number or URL" do
      command = instance_double(TTY::Command)
      allow(command).to receive(:run).and_return(instance_double(TTY::Command::Result, out: payload))

      expect(described_class.new(command:).pull_request("12")).to include(number: 12, state: "Merged 🟣", body: "Adds /healthz.")
    end

    # PrWatch asks for a pull request `gh pr list` left out, and reads it as
    # it reads a row of #pulls.
    it "carries the open flag and labels a row of #pulls carries" do
      command = instance_double(TTY::Command)
      allow(command).to receive(:run).and_return(instance_double(TTY::Command::Result, out: payload))

      expect(described_class.new(command:).pull_request("12")).to include(open: false, labels: ["ready-to-merge"])
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

  describe "review labels, checks and comments" do
    let(:label) { OpenLanes::Plans::ReviewLabel::INITIAL }
    let(:argvs) { [] }

    def exit_error(stderr)
      TTY::Command::ExitError.new("gh",
        instance_double(TTY::Command::Result, exit_status: 1, out: "", err: stderr))
    end

    before do
      allow(command).to receive(:run) do |*argv|
        argvs << argv
        instance_double(TTY::Command::Result, out: JSON.generate("labels" => [{ "name" => "review-in-progress" }]))
      end
    end

    it "carries each pull request's labels on #pulls" do
      allow(command).to receive(:run).and_return(
        instance_double(TTY::Command::Result,
          out: JSON.generate([{ "number" => 1, "state" => "MERGED", "mergedAt" => "x", "labels" => [{ "name" => "ready-to-merge" }] }]))
      )
      expect(github.pulls.first).to include(labels: ["ready-to-merge"], state: "Merged 🟣", open: false)
    end

    it "creates a missing label with its colour and meaning, never --force" do
      github.ensure_label(label, repo: "o/r")

      expect(argvs).to eq([["gh", "label", "create", "ready-for-review", "--color", "c2e0c6",
                            "--description", label.meaning, "-R", "o/r"]])
    end

    it "leaves an existing label alone" do
      allow(command).to receive(:run).and_raise(exit_error("label with name \"ready-for-review\" already exists"))

      expect { github.ensure_label(label) }.not_to raise_error
    end

    it "surfaces the first stderr line when creating fails otherwise" do
      allow(command).to receive(:run).and_raise(exit_error("HTTP 403: forbidden\nmore"))

      expect { github.ensure_label(label) }.to raise_error(OpenLanes::Error, "could not create label ready-for-review: HTTP 403: forbidden")
    end

    it "swaps labels in one edit, with -R, and returns what is left" do
      left = github.swap_label(number: 12,
        repo: "o/r",
        add: OpenLanes::Plans::ReviewLabel.fetch("review-in-progress"),
        remove: %w[ready-for-review review-in-progress])

      aggregate_failures do
        expect(argvs[1]).to eq(%w[gh pr edit 12 --add-label review-in-progress --remove-label ready-for-review -R o/r])
        expect(left).to eq(["review-in-progress"])
        expect(argvs.flatten).not_to include("--force")
      end
    end

    it "tolerates removing a label the pull request lacks, by retrying without it" do
      calls = 0
      allow(command).to receive(:run) do |*argv|
        argvs << argv
        calls += 1
        raise exit_error("'review-rejected' not found") if calls == 2

        instance_double(TTY::Command::Result, out: JSON.generate("labels" => []))
      end

      github.swap_label(number: 12, add: label, remove: %w[review-rejected])

      aggregate_failures do
        expect(argvs[2]).to eq(%w[gh pr view 12 --json labels])
        expect(argvs[3]).to eq(%w[gh pr edit 12 --add-label ready-for-review])
      end
    end

    it "still takes off a stale review label the pull request does carry when the first edit fails" do
      calls = 0
      allow(command).to receive(:run) do |*argv|
        argvs << argv
        calls += 1
        raise exit_error("'review-ok-not-perfect' not found") if calls == 2

        instance_double(TTY::Command::Result, out: JSON.generate("labels" => [{ "name" => "review-rejected" }]))
      end

      github.swap_label(number: 12, add: label, remove: %w[review-rejected review-ok-not-perfect])

      expect(argvs[3]).to eq(%w[gh pr edit 12 --add-label ready-for-review --remove-label review-rejected])
    end

    it "surfaces a retry that fails too, rather than reporting success" do
      allow(command).to receive(:run).with("gh", "label", any_args)
      carried = instance_double(TTY::Command::Result, out: JSON.generate("labels" => [{ "name" => "review-rejected" }]))
      allow(command).to receive(:run).with("gh", "pr", "view", any_args).and_return(carried)
      allow(command).to receive(:run).with("gh", "pr", "edit", any_args).and_raise(exit_error("HTTP 403"))

      expect { github.swap_label(number: 12, add: label, remove: %w[review-rejected]) }
        .to raise_error(OpenLanes::Error, /could not label #12: HTTP 403/)
    end

    it "fails loudly when the add itself fails" do
      allow(command).to receive(:run).with("gh", "label", any_args)
      allow(command).to receive(:run).with("gh", "pr", "edit", any_args).and_raise(exit_error("no such PR"))

      expect { github.swap_label(number: 12, add: label) }.to raise_error(OpenLanes::Error, /could not label #12: no such PR/)
    end

    describe "#label_colours" do
      it "lists the repository's labels by name, colours in lower case" do
        allow(command).to receive(:run).and_return(
          instance_double(TTY::Command::Result,
            out: JSON.generate([{ "name" => "review-rejected", "color" => "B60205" }, { "name" => "bug", "color" => "d73a4a" }]))
        )

        aggregate_failures do
          expect(github.label_colours(repo: "o/r")).to eq("review-rejected" => "b60205", "bug" => "d73a4a")
          expect(command).to have_received(:run)
            .with("gh", "label", "list", "--limit", "1000", "--json", "name,color", "-R", "o/r")
        end
      end

      it "names the failure when gh cannot list them" do
        allow(command).to receive(:run).and_raise(exit_error("HTTP 401"))

        expect { github.label_colours }.to raise_error(OpenLanes::Error, /could not list labels: HTTP 401/)
      end

      # A CI image without gh: the sync's caller warns on Error and carries on.
      it "names the failure when gh is not installed" do
        allow(command).to receive(:run).and_raise(Errno::ENOENT, "gh")

        expect { github.label_colours }.to raise_error(OpenLanes::Error, /could not list labels: No such file or directory - gh/)
      end
    end

    describe "#recolour_label" do
      let(:rejected) { OpenLanes::Plans::ReviewLabel::REJECTED }

      it "edits the colour and description of an existing label" do
        github.recolour_label(rejected)

        expect(argvs.last).to eq(["gh", "label", "edit", "review-rejected", "--color", "F90000",
                                  "--description", rejected.meaning])
      end

      it "names the label it could not recolour" do
        allow(command).to receive(:run).and_raise(exit_error("HTTP 403"))

        expect { github.recolour_label(rejected, repo: "o/r") }
          .to raise_error(OpenLanes::Error, /could not recolour label review-rejected: HTTP 403/)
      end
    end

    describe "#checks" do
      def checks_result(out:, err: "", success: false)
        instance_double(TTY::Command::Result, out:, err:, success?: success)
      end

      it "parses buckets, whatever gh's exit status" do
        allow(command).to receive(:run!).and_return(checks_result(out: JSON.generate([{ "name" => "rspec", "state" => "FAILURE", "bucket" => "fail" }])))

        expect(github.checks(number: 3, repo: "o/r")).to eq([{ name: "rspec", bucket: "fail" }])
        expect(command).to have_received(:run!).with("gh", "pr", "checks", "3", "--json", "name,state,bucket", "-R", "o/r")
      end

      it "returns none when gh reports no checks" do
        allow(command).to receive(:run!).and_return(checks_result(out: "", err: "no checks reported on the 'x' branch"))

        expect(github.checks(number: 3)).to eq([])
      end

      it "raises on any other silent failure" do
        allow(command).to receive(:run!).and_return(checks_result(out: "", err: "HTTP 401\n"))

        expect { github.checks(number: 3) }.to raise_error(OpenLanes::Error, "could not read checks of #3: HTTP 401")
      end

      it "raises on output it cannot parse" do
        allow(command).to receive(:run!).and_return(checks_result(out: "nope"))

        expect { github.checks(number: 3) }.to raise_error(OpenLanes::Error, /could not read checks of #3/)
      end
    end

    it "reads conversation comments and reviews, skipping empty bodies" do
      allow(command).to receive(:run).and_return(instance_double(TTY::Command::Result,
        out: JSON.generate(
          "comments" => [{ "author" => { "login" => "octo" }, "body" => "Fix the nil", "url" => "u1" }],
          "reviews"  => [{ "author" => { "login" => "hansolo" }, "body" => "", "url" => "u2" },
                         { "author" => { "login" => "hansolo" }, "body" => "Rejected", "url" => "u3" }]
        )))

      expect(github.review_comments(number: 4)).to eq([
                                                        { author: "octo", body: "Fix the nil", url: "u1" },
                                                        { author: "hansolo", body: "Rejected", url: "u3" }
                                                      ])
    end

    it "surfaces a failed comment read" do
      allow(command).to receive(:run).and_raise(exit_error("boom"))

      expect { github.review_comments(number: 4) }.to raise_error(OpenLanes::Error, /could not read comments of #4: boom/)
    end

    it "surfaces a failed label read" do
      allow(command).to receive(:run).and_raise(exit_error("boom"))

      expect { github.labels(number: 4) }.to raise_error(OpenLanes::Error, /could not read labels of #4: boom/)
    end

    it "takes owner/repo out of a pull request URL" do
      expect(described_class.repo_of("https://github.com/o/r/pull/9")).to eq("o/r")
      expect(described_class.repo_of("12")).to be_nil
    end
  end
end
