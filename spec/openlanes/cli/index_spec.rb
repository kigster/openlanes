# frozen_string_literal: true

# `openlanes index` writes a file by default and prints it with `-o -`. The
# examples pin both destinations, because a page written where nobody asked —
# or printed when a file was wanted — is a deliverable silently misdelivered.
RSpec.describe OpenLanes::CLI::Index, :tree do
  subject(:command) { described_class.new }

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  before { plans { |t| t.plan("001.00", :new, "tax-rule-dsl", files: { "spec.md" => spec_body }) } }

  it "writes INDEX.md into the plans directory and prints where" do
    out, err, = run

    path = File.join(plans_root, "INDEX.md")
    expect(out.strip).to eq(path)
    expect(File.read(path)).to include("001.00")
    # The box wraps a temp path mid-word, so the sentence is asserted on its
    # stable parts rather than the whole absolute path.
    expect(unwrapped(err)).to include("Wrote", "INDEX.md", "resync dirs")
  end

  it "prints the page instead when -o - asks for STDOUT" do
    out, = run(output: "-")

    expect(out).to include("001.00")
    expect(File.exist?(File.join(plans_root, "INDEX.md"))).to be(false)
  end

  it "takes the heading from --project rather than the directory name" do
    out, = run(output: "-", project: "Equilibris App")

    expect(out).to include("Equilibris App")
  end

  it "says only the path under --quiet" do
    _out, err, = run(quiet: true)

    expect(err).to eq("")
  end

  # `-D` pointing nowhere must fail loudly: an index of an empty default tree
  # looks exactly like an index of the tree the user meant, minus the plans.
  it "refuses when the plans directory is not there" do
    _out, err, status = run(dir: File.join(plans_root, "nope"))

    expect(unwrapped(err)).to include("No .plans directory")
    expect(status).to eq(66)
  end
end
