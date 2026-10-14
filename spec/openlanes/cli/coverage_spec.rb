# frozen_string_literal: true

require "open3"

# `openlanes coverage` runs a real command in a real worktree of a real
# repository; only the seeder is replaced, so no `.env` from this machine
# is copied anywhere.
RSpec.describe "openlanes coverage", :tree do
  let(:root) { File.dirname(plans_root) }
  let(:worktree) { File.join("#{root}.worktrees", "001.00-gate") }

  before do
    plans { |t| t.plan "001.00", :ready_for_review, "gate", files: { "spec.md" => "# Gate\n" } }
    stub_const("ENV", ENV.to_h.merge("OPENLANES_SETUP_WORKTREE" => "/usr/bin/true"))
  end

  after { FileUtils.rm_rf("#{root}.worktrees") }

  def commit(hit:, minimum: 95)
    File.write(File.join(root, ".openlanes.coverage.yml"),
      YAML.dump(
        "command" => "mkdir -p coverage && printf 'SF:a\\nLF:10000\\nLH:#{hit}\\nend_of_record\\n' > coverage/lcov.info",
        "report"  => "coverage/lcov.info",
        "format"  => "lcov",
        "minimum" => minimum
      ))
    File.write(File.join(root, ".gitignore"), "coverage/\n")
    git = ->(*args) { Open3.capture2e("git", "-C", root, *args).last.success? or raise "git #{args.join(" ")} failed" }
    git.call("init", "-q", "-b", "main")
    git.call("add", "-A")
    git.call("-c", "user.name=Fixture", "-c", "user.email=fixture@example.com", "commit", "-q", "-m", "fixture")
  end

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      OpenLanes::CLI::Coverage.new.call(dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  it "passes at the minimum, in the plan's worktree" do
    commit(hit: 9500)
    out, _err, status = run(plan: "001")

    expect([status, out]).to eq([0, "coverage 95.00% meets the 95% minimum (lcov: coverage/lcov.info)\n"])
    expect(File).to exist(File.join(worktree, "coverage/lcov.info"))
    expect(File).not_to exist(File.join(root, "coverage"))
  end

  it "withholds below the minimum and exits 1" do
    commit(hit: 9499)
    out, _err, status = run(plan: "001")

    expect([status, out]).to eq([1, "ok-to-merge withheld: coverage 94.99% is below the 95% minimum (lcov: coverage/lcov.info)\n"])
  end

  it "refuses a plan the tree does not hold" do
    commit(hit: 9500)
    _out, err, status = run(plan: "009")

    expect([status, err]).to match([66, a_string_including("No plan 009")])
  end

  it "refuses a project that is not a git repository" do
    _out, err, status = run(plan: "001")

    expect([status, err]).to match([66, a_string_including("is not a git repository")])
  end

  it "previews without creating the worktree or running anything" do
    commit(hit: 9500)
    out, err, status = run(plan: "001", dry_run: true)

    expect(status).to eq(0)
    expect(out).to include("would run in #{worktree}", "once the worktree exists")
    expect(err).to include("nothing was changed")
    expect(File).not_to exist(worktree)
  end

  it "previews the declaration once the worktree exists" do
    commit(hit: 9500)
    run(plan: "001")
    out, = run(plan: "001", dry_run: true)

    expect(out).to include("then read coverage/lcov.info (lcov), minimum 95%")
  end

  it "refuses a preview of an invalid declaration" do
    commit(hit: 9500)
    run(plan: "001")
    File.write(File.join(worktree, ".openlanes.coverage.yml"), "command: true\n")
    _out, err, status = run(plan: "001", dry_run: true)

    expect([status, err]).to match([65, a_string_including("missing key")])
  end

  it "shows the command's output on STDERR when it withholds" do
    commit(hit: 9500)
    run(plan: "001")
    File.write(File.join(worktree, ".openlanes.coverage.yml"),
      YAML.dump("command" => "echo boom; exit 2", "report" => "r", "format" => "lcov", "minimum" => 95))
    Open3.capture2e("git", "-C", worktree, "-c", "user.name=F", "-c", "user.email=f@example.com", "commit", "-qam", "x")
    out, err, status = run(plan: "001")

    expect([status, out, err]).to match([1, a_string_including("exited 2"), a_string_including("boom")])
  end
end
