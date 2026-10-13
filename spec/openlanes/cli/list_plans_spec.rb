# frozen_string_literal: true

# `openlanes list-plans` backs /plan-status and is read by scripts, so the
# table goes to STDOUT whole — and the exit status is the one machine-readable
# fact about tree health, so a folder whose name lies must turn it non-zero.
RSpec.describe OpenLanes::CLI::ListPlans, :tree do
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

  it "prints every plan on STDOUT and exits zero when the names hold" do
    plans { |t| t.plan("001.00", :new, "tax-rule-dsl", files: { "spec.md" => spec_body }) }
    out, _err, status = run

    expect(out).to include("001.00", "Tax Rule DSL")
    expect(status).to eq(0)
  end

  # ⭕️ with an unreadable blocked.md is a name the contents do not justify.
  # Exiting zero here would let CI treat a lying tree as a healthy one.
  it "exits non-zero when a folder's contents do not justify its name" do
    plans { |t| t.plan("002.00", :blocked, "stuck", files: { "blocked.md" => "# Blocked\n\nno numbered question\n" }) }
    _out, _err, status = run

    expect(status).to eq(1)
  end

  it "says so when the tree is empty rather than printing a bare header" do
    out, _err, status = run

    expect(out).to include("No plans found")
    expect(status).to eq(0)
  end
end
