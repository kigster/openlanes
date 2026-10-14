# frozen_string_literal: true

# Both resyncs write to things other tools join on — folder names, pull
# request titles — so the property under test throughout is candour: a dry run
# says it changed nothing, a commit says exactly what it changed, and anything
# too ambiguous to touch is reported rather than skipped in silence.
RSpec.describe "openlanes resync", :tree do
  def run(command, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dir: plans_root, dry_run: true, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  describe OpenLanes::CLI::Resync::Dirs do
    subject(:command) { described_class.new }

    it "says every folder already holds when there is nothing to do" do
      plans { |t| t.plan("001.00", :new, "fine", files: { "spec.md" => spec_body }) }
      out, err, = run(command)

      expect(out).to eq("")
      expect(unwrapped(err)).to include("already named")
    end

    context "with a folder whose contents outgrew its name" do
      before do
        # A ⚪ folder that has grown a plan.md with work units best-fits ⭐ whatever its name says.
        plans { |t| t.plan("001.00", :new, "outgrown", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }) }
      end

      it "prints the rename as a machine-readable row and leaves the disk alone" do
        out, err, = run(command)

        expect(out).to include("001.00━━⚪━━❯outgrown\t001.00━━⭐━━❯outgrown")
        expect(Dir.children(plans_root)).to include("001.00━━⚪━━❯outgrown")
        expect(unwrapped(err)).to include("1 rename pending", "without --dry-run")
      end

      it "renames without --dry-run and says how many folders moved" do
        _out, err, = run(command, dry_run: false)

        expect(Dir.children(plans_root)).to include("001.00━━⭐━━❯outgrown")
        expect(unwrapped(err)).to include("Renamed 1 folder")
      end

      it "keeps the rows and drops the prose under --quiet" do
        out, err, = run(command, quiet: true)

        expect(out).to include("001.00━━⚪━━❯outgrown")
        expect(err).to eq("")
      end
    end
  end

  describe OpenLanes::CLI::Resync::Prs do
    subject(:command) { described_class.new }

    let(:github) { instance_double(OpenLanes::Vcs::GitHub) }

    before { allow(OpenLanes::Vcs::GitHub).to receive(:new).and_return(github) }

    def pull(number, title, branch: "", files: [])
      { number:, title:, url: "https://github.com/example/repo/pull/#{number}",
       branch:, files:, state: "Open 🟡", open: true }
    end

    it "says every title already carries a prefix when they all do" do
      allow(github).to receive(:pulls).and_return([pull(1, "[001.00] Done already")])
      out, err, = run(command)

      expect(out).to eq("")
      expect(unwrapped(err)).to include("already carries a prefix")
    end

    context "with titles to resolve" do
      before do
        plans { |t| t.plan("001.00", :new, "tax-rule-dsl", files: { "spec.md" => spec_body }) }
        allow(github).to receive(:pulls).and_return([
                                                      pull(7, "Add the DSL", branch: "kig/001.00-tax-rule-dsl"),
                                                      pull(9, "Bump CI cache")
                                                    ])
      end

      it "previews each retitle as a row without touching GitHub" do
        out, = run(command, adopt: false)

        expect(out).to include("7\t[001.00] Add the DSL\tbranch kig/001.00-tax-rule-dsl")
        expect(out).to include("9\t[dev] Bump CI cache")
      end

      # `[dev]` on a title nothing resolved is an assertion about intent that
      # only the author can make, so the tool must say it is assuming.
      it "warns that the no-plan prefix is an assumption, not a fact" do
        _out, err, = run(command, adopt: false)

        expect(unwrapped(err)).to include("would get [dev] because no plan resolved", "2 retitles pending")
      end

      it "retitles through the seam without --dry-run and reports the count" do
        allow(github).to receive(:retitle)
        _out, err, = run(command, adopt: false, dry_run: false)

        expect(github).to have_received(:retitle).with(number: 7, title: "[001.00] Add the DSL")
        expect(unwrapped(err)).to include("Retitled 2 pull requests")
      end
    end

    context "with a pull request nothing can resolve safely" do
      before do
        plans { |t| t.plan("001.00", :new, "tax-rule-dsl", files: { "spec.md" => spec_body }) }
        # The branch names a plan the tree does not hold, which is exactly the
        # case where writing any number would file work under the wrong plan.
        allow(github).to receive(:pulls).and_return([pull(4, "Mystery work", branch: "kig/099.00-mystery")])
      end

      it "flags it for a human under --no-adopt rather than editing it" do
        out, err, = run(command, adopt: false)

        expect(out).to include("4\t-\tbranch names 099.00")
        expect(unwrapped(err)).to include("SKIPPED")
      end

      # With adoption on, the answer to "no plan describes this" is a plan.
      it "proposes a retroactive folder for it by default" do
        out, err, = run(command)

        expect(out).to include("adopted into")
        expect(unwrapped(err)).to include("Would create 1 plan folder", "openlanes run`")
      end
    end

    it "reports a gh that cannot answer instead of a stack trace" do
      allow(github).to receive(:pulls).and_raise(OpenLanes::Error, "could not list pull requests via `gh`: boom")
      _out, err, status = run(command)

      expect(unwrapped(err)).to include("could not list pull requests")
      expect(status).to eq(69)
    end
  end
end
