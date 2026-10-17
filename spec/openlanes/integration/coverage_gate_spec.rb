# frozen_string_literal: true

require "open3"

# The integration check for plan 013: a real repository, a real plan, a real
# test command, and the real executable, nothing stubbed. Only the worktree
# seeder is pointed at `true`, so no file from this machine is copied in.
RSpec.describe "the coverage gate, end to end" do
  let(:exe) { File.expand_path("../../../exe/openlanes", __dir__) }
  let(:root) { File.realpath(Dir.mktmpdir("coverage-gate-e2e")) }
  let(:worktree) { File.join("#{root}.worktrees", "001.00-gate") }

  after { FileUtils.rm_rf([root, "#{root}.worktrees"]) }

  # @param command [String] the declared test command
  def project(command)
    PlansFixture::Builder.new(File.join(root, OpenLanes::PLANS_DIR))
                         .plan("001.00", :ready_for_review, "gate", files: { "spec.md" => "# Gate\n" })
    File.write(File.join(root, ".openlanes.yml"),
      YAML.dump("coverage" => { "command" => command, "report" => "coverage/lcov.info", "format" => "lcov", "minimum" => 95 }))
    File.write(File.join(root, ".gitignore"), "coverage/\n")
    [%w[init -q -b main], %w[add -A], %w[-c user.name=Fixture -c user.email=fixture@example.com commit -q -m fixture]]
      .each { |args| Open3.capture2e("git", "-C", root, *args).last.success? or raise "git #{args.join(" ")} failed" }
  end

  def lcov(hit) = "mkdir -p coverage && printf 'SF:lib/a.rb\\nLF:10000\\nLH:#{hit}\\nend_of_record\\n' > coverage/lcov.info"

  def gate
    out, err, status = Open3.capture3({ "NO_COLOR" => "1", "OPENLANES_SETUP_WORKTREE" => "/usr/bin/true" },
      exe,
      "coverage",
      "001",
      chdir: root)
    [out, err, status.exitstatus]
  end

  it "passes at 95.00% with a 95 minimum, having run in the plan's worktree" do
    project(lcov(9500))
    out, err, status = gate

    expect([status, out]).to eq([0, "coverage 95.00% meets the 95% minimum (lcov: coverage/lcov.info)\n"]), err
    expect(File).to exist(File.join(worktree, "coverage/lcov.info"))
    expect(File).not_to exist(File.join(root, "coverage"))
  end

  it "withholds at 94.99% and prints the figure and the minimum" do
    project(lcov(9499))
    out, _err, status = gate

    expect([status, out]).to eq([1, "ready-to-merge withheld: coverage 94.99% is below the 95% minimum (lcov: coverage/lcov.info)\n"])
  end

  it "withholds when the command writes no report, counting it as 0%" do
    project("true")
    out, _err, status = gate

    expect(status).to eq(1)
    expect(out).to match(%r{\Aready-to-merge withheld: coverage counts as 0%: .*coverage/lcov.info is missing\n\z})
  end
end
