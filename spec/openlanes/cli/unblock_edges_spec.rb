# frozen_string_literal: true

# Edges of `openlanes unblock` that spec/openlanes/cli/unblock_spec.rb leaves
# open: `--agent` naming nobody, and the dry-run footer's grammar once more
# than one plan is on the table. Small, but each is a sentence a human reads.
RSpec.describe OpenLanes::CLI::Unblock, :tree do
  subject(:command) { described_class.new }

  def run(*plans, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(plans:, dir: plans_root, dry_run: true, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  def blocked_plan(ordinal)
    plans { |t| t.plan(ordinal, :blocked, "stuck-#{ordinal.tr(".", "-")}", files: { "blocked.md" => "# Blocked\n\n## B1. Which vendor\n" }) }
  end

  describe "--agent naming nobody" do
    it "refuses before resolving any plan, listing who exists" do
      blocked_plan("001.00")
      _out, err, status = run("001", agent: "chewbacca")

      expect(unwrapped(err)).to include("No agent called chewbacca", "lando-broker")
      expect(status).to eq(65)
    end
  end

  describe "a dry run over several plans" do
    it "counts them in the plural, so the footer reads as written by a person" do
      blocked_plan("001.00")
      blocked_plan("002.00")
      _out, err, = run("001", "002")

      expect(unwrapped(err)).to include("2 plans are unchanged")
    end
  end
end
