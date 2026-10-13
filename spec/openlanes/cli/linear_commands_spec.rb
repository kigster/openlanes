# frozen_string_literal: true

# The linear commands touch a paid, shared tracker, so the seams matter more
# than anywhere else: {Linear::API} is replaced throughout, and the examples
# pin which paths reach for it at all — `--format json` exists precisely to
# work without a token, and a bad team key must fail before authentication.
RSpec.describe "openlanes linear", :tree do
  def run(command, team:, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(team:, dir: plans_root, dry_run: true, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  let(:api) { instance_double(OpenLanes::Linear::API) }

  def with_api(projects)
    allow(OpenLanes::Linear::API).to receive_messages(token_from_env: "lin_api_test", new: api)
    allow(api).to receive(:team).with("TAX").and_return({ id: "team-1" })
    allow(api).to receive(:projects).with("team-1").and_return(projects)
  end

  def project(name, url: "https://linear.app/acme/project/#{name.downcase.tr(" ", "-")}", description: "")
    { "id" => "proj-#{name.downcase.tr(" ", "-")}", "name" => name, "url" => url,
     "status" => { "name" => "Planned" }, "description" => description }
  end

  describe OpenLanes::CLI::Linear::Projects do
    subject(:command) { described_class.new }

    it "lists each project as a row on STDOUT and prose on STDERR" do
      with_api([project("Tax Rule DSL", description: "The rules engine, as a language.")])
      out, err, = run(command, team: "TAX")

      expect(out).to include("Tax Rule DSL\tPlanned\thttps://linear.app/acme/project/tax-rule-dsl")
      expect(err).to include("Tax Rule DSL")
    end

    # A project with no description gives the import nothing to reason about,
    # and the person who can fix that is the one reading this output.
    it "calls out projects that say nothing about themselves" do
      with_api([project("Mystery")])
      _out, err, = run(command, team: "TAX")

      expect(unwrapped(err)).to include("1 of these say nothing about themselves", "Mystery")
    end

    # The key is checked before anything reaches for a token, so a typo
    # reports the typo rather than an authentication problem nobody has.
    it "refuses a malformed team key before touching the network" do
      allow(OpenLanes::Linear::API).to receive(:new) { raise "the key check must come before authentication" }
      _out, err, status = run(command, team: "not a key")

      expect(unwrapped(err)).to include("not a Linear team key")
      expect(status).to eq(69)
    end
  end

  describe OpenLanes::CLI::Linear::Import do
    subject(:command) { described_class.new }

    before do
      plans do |t|
        t.plan("001.00", :new, "tax-rule-dsl", files: { "spec.md" => spec_body })
      end
    end

    # A tool that picks a project when you forget to say which is a tool that
    # files a quarter of somebody's work in the wrong place.
    it "refuses to run without a project named" do
      _out, err, status = run(command, team: "TAX")

      expect(unwrapped(err)).to include("which project?", "openlanes linear projects")
      expect(status).to eq(69)
    end

    context "offline, project by name" do
      before { allow(OpenLanes::Linear::API).to receive(:token_from_env).and_return(nil) }

      it "previews every pending action without a token or a lookup" do
        out, err, = run(command, team: "TAX", project: "Tax Rule DSL")

        expect(out).to include("create\tissue\t001.00")
        expect(unwrapped(err)).to include("1 Linear change pending", "without --dry-run")
      end

      # The command has no push of its own, so a real run must not read as
      # though something reached Linear.
      it "says nothing was sent when run without --dry-run" do
        _out, err, = run(command, team: "TAX", project: "Tax Rule DSL", dry_run: false)

        expect(unwrapped(err)).to include("1 Linear change pending — nothing was sent", "--format json")
      end

      it "emits the exact MCP arguments under --format json" do
        out, err, = run(command, team: "TAX", project: "Tax Rule DSL", format: "json")

        decoded = JSON.parse(out)
        expect(decoded["team"]).to eq("TAX")
        expect(decoded["actions"].first["title"]).to include("[001.00]")
        expect(err).to eq("")
      end

      it "says Linear is already in step when the filters leave nothing" do
        _out, err, = run(command, team: "TAX", project: "Tax Rule DSL", since: "900.00")

        expect(unwrapped(err)).to include("already in step")
      end

      it "filters to the named states" do
        out, = run(command, team: "TAX", project: "Tax Rule DSL", status: "planned")

        expect(out).to eq("")
      end

      # A typo'd state silently importing the whole tree is the failure this
      # refusal exists to prevent.
      it "refuses a state that does not exist" do
        _out, err, status = run(command, team: "TAX", project: "Tax Rule DSL", status: "shipped")

        expect(unwrapped(err)).to include("no such state: shipped")
        expect(status).to eq(69)
      end

      # 💩 and 😱 have no decided place on a board; guessing would file them
      # in a column that reads exactly like the right one.
      it "reports the states nothing knows where to file" do
        plans { |t| t.plan("002.00", :shit, "scrapped", files: { "rewrite.md" => "# Rewrite" }) }
        _out, err, = run(command, team: "TAX", project: "Tax Rule DSL")

        expect(unwrapped(err)).to include("Not imported", "002.00", "Linear::PLACEMENTS")
      end
    end

    # A URL carries no name, so it is the one reference that forces a lookup.
    it "resolves a project URL through the API" do
      with_api([project("Tax Rule DSL")])
      out, = run(command,
        team:    "TAX",
        project: "https://linear.app/acme/project/tax-rule-dsl")

      expect(out).to include("create\tissue\t001.00")
    end
  end
end
