# frozen_string_literal: true

# `openlanes api docs` against a real plans tree: the contracts on STDOUT,
# what is wrong with them on STDERR, and an exit status a script can test.
RSpec.describe "openlanes api docs", :tree do
  let(:valid) { "openapi: 3.1.0\ninfo:\n  title: Returns\n  version: \"1\"\npaths: {}\n" }

  def plan_with(ordinal, slug, openapi)
    plans { |t| t.plan ordinal, :building, slug, files: { "spec.md" => spec_body, "plan.md" => "# P", "openapi.yaml" => openapi } }
  end

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      OpenLanes::CLI::API::Docs.new.call(dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  it "is registered as `api docs`" do
    expect(OpenLanes::CLI.get(%w[api docs]).command).to eq(OpenLanes::CLI::API::Docs)
  end

  context "when every contract is good" do
    before { plan_with("001.00", "returns", valid) }

    it "prints each file with its title and the command that renders it, and exits 0" do
      out, err, status = run

      aggregate_failures do
        expect(status).to eq(0)
        expect(out).to include("openapi.yaml  (Returns — OpenAPI 3.1.0)", "npx @redocly/cli build-docs ", "openapi.html")
        expect(err).not_to include("openapi.yaml")
      end
    end
  end

  context "when one contract is bad" do
    before do
      plan_with("001.00", "returns", valid)
      plan_with("002.00", "half-written", "openapi: 3.1.0\n")
    end

    it "keeps the good one on STDOUT, puts the bad one on STDERR, and exits 65" do
      out, err, status = run

      aggregate_failures do
        expect(status).to eq(65)
        expect([out.include?("returns"), out.include?("half-written")]).to eq([true, false])
        expect(err).to include("half-written", "has no top-level paths:")
      end
    end

    it "still reports the problem under --quiet" do
      _out, err, status = run(quiet: true)

      expect([status, err]).to match([65, include("has no top-level paths:")])
    end
  end

  it "says so on STDERR when no plan carries a contract, and exits 0" do
    plans { |t| t.plan "001.00", :building, "plain", files: { "spec.md" => spec_body, "plan.md" => "# P" } }
    out, err, status = run

    expect([out, err, status]).to match(["", include("No openapi.yaml in"), 0])
  end
end
