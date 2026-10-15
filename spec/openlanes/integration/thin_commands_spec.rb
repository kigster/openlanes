# frozen_string_literal: true

require "open3"

# The integration check for plan 002.00: the real `exe/openlanes`, spawned
# in a fixture project, nothing stubbed. Each slimmed command answers through
# its workflow with the output and the exit status it always had.
#
# A fake `claude` (and `codex`, `pi`) that exits 1 sits first on PATH and
# BUNDLER_ORIG_PATH, so a regression that reached for an agent CLI fails
# here rather than spending money. None of these commands should reach one.
RSpec.describe "the slimmed commands, end to end", :tree do
  let(:exe) { File.expand_path("../../../exe/openlanes", __dir__) }
  let(:project) { File.dirname(plans_root) }

  let(:fake_bin) do
    Dir.mktmpdir("fake-agents").tap do |dir|
      %w[claude codex pi].each do |name|
        path = File.join(dir, name)
        File.write(path, "#!/bin/sh\necho 'fake #{name} must not run' >&2\nexit 1\n")
        File.chmod(0o755, path)
      end
    end
  end

  let(:env) do
    path = "#{fake_bin}:#{ENV.fetch("PATH", "")}"
    { "NO_COLOR" => "1", "PATH" => path, "BUNDLER_ORIG_PATH" => path, "REDIS_URL" => "redis://127.0.0.1:1/15" }
  end

  def openlanes(*argv)
    out, err, status = Open3.capture3(env, exe, *argv, chdir: project)
    [out, err, status.exitstatus]
  end

  before do
    plans do |t|
      t.plan("001.00", :building, "tax-rule-dsl", files: { "spec.md" => spec_body, "plan.md" => "# Plan" })
      t.plan("002.00",
        :blocked,
        "vendor-choice",
        files: { "spec.md" => spec_body, "blocked.md" => "# Blocked\n\n## B1. Which vendor\n" })
    end
  end

  it "create prints the new folder and exits 0" do
    out, _err, status = openlanes("create", "billing", "sync", "--no-draft", "--no-open")

    expect([status, File.basename(out.strip)]).to eq([0, "003.00━━⚪━━❯billing-sync"])
  end

  it "create refuses a seed file that is not there with 66" do
    _out, err, status = openlanes("create", "--from", "missing.md", "--no-draft", "--no-open")

    expect([status, err]).to match([66, a_string_including("does not exist")])
  end

  it "unblock previews the open question and exits 0" do
    out, err, status = openlanes("unblock", "002", "-n")

    expect([status, out, err]).to match([0, a_string_including("002.00\tblocked\t1 open\tnot attempted"),
                                         a_string_including("B1. Which vendor")])
  end

  it "unblock refuses a plan that is not there with 66" do
    expect(openlanes("unblock", "999", "-n").last).to eq(66)
  end

  it "run previews the assignment and exits 0" do
    out, _err, status = openlanes("run",
      "-n",
      "--isolation",
      "shared",
      "--no-web",
      "--log",
      File.join(project, "progress.log"))

    expect([status, out]).to match([0, a_string_including("001.00  luke-backend")])
  end

  it "run refuses an unknown agent with 65" do
    _out, err, status = openlanes("run", "-n", "--isolation", "shared", "--no-web", "--agent", "nobody")

    expect([status, err]).to match([65, a_string_including("No agent called nobody")])
  end
end
