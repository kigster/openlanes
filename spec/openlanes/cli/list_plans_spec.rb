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

  def capture_stdout
    out = StringIO.new
    original = $stdout
    $stdout = out
    yield
    out.string
  ensure
    $stdout = original
  end

  describe "dependencies" do
    let(:dependent_spec) { "---\ndepends_on: [\"034.00\"]\n---\n#{spec_body}" }

    before do
      plans do |t|
        t.plan("034.00", :new, "base", files: { "spec.md" => spec_body })
        t.plan("050.00", :new, "later", files: { "spec.md" => dependent_spec })
      end
    end

    it "reads blocks 050.00 on the 034 row" do
      out, _err, _status = run

      expect(out.lines.find { |l| l.include?("034.00") }).to include("blocks 050.00")
    end

    it "keeps the note when colour is on" do
      allow(OpenLanes::UI).to receive(:color?).and_return(true)
      printed = capture_stdout { command.call(dir: plans_root) }

      expect(strip_ansi(printed)).to include("blocks 050.00")
    end
  end
end
