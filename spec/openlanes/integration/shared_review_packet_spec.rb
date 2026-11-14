# frozen_string_literal: true

# 060.00 B6b, point 4: the three reviewers of one plan start from one review
# packet. A real Runner, dispatcher and Executor, with a real ReviewPacket
# over a doubled `gh`; the agent CLI is a played-back stream. The diff is
# fetched once, and every reviewer's prompt carries the same packet.
RSpec.describe "Shared review packet", :tree do
  before do
    Dir.chdir(File.dirname(plans_root))
    [spawned, prompts, stamp]
    plans { |t| t.plan "001.00", :ready_for_review, "tic-tac-toe", files:, prs: }
  end

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(shelf)
  end

  let(:stamp) { "2026-09-04 11:29:20 AM PDT" }
  let(:spawned) { [] }
  let(:prompts) { [] }
  let(:shelf) { Dir.mktmpdir("packets") }
  let(:prs) { [{ number: 12, title: "Tic Tac Toe", url: "https://github.com/example/repo/pull/12", state: "open" }] }
  let(:files) { { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## How to test\n\n- run it\n" } }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub, diff: "diff --git a/lib/a.rb b/lib/a.rb\n+added line\n") }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:state) { OpenLanes::Engine::StateFile.new(path: OpenLanes::Engine::StateFile.for(tree)) }
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:reviewers) { %w[staff-reviewer design-reviewer security-reviewer] }
  let(:executor) do
    root = File.dirname(plans_root)
    sign = method(:sign)
    OpenLanes::Execution::Executor.new(root:,
      trace_dir: File.join(root, "traces"),
      packets:   OpenLanes::Execution::ReviewPacket.new(github:, dir: shelf),
      spawn:     lambda { |argv, **|
        spawned << argv
        prompts << argv.join(" ")
        sign.call(reviewers.find { |name| argv.join(" ").include?(name) })
        child
      })
  end

  def child
    child = instance_double(OpenLanes::Execution::Child, pid: 100 + spawned.size, alive?: false, kill: nil, terminate: nil, wait: ok)
    init = "#{JSON.generate(type: "system", subtype: "init", session_id: "sess-#{spawned.size}")}\n"
    allow(child).to receive(:each_chunk).and_yield(init)
    child
  end

  # What each reviewer would have signed before it exited.
  def sign(name)
    return unless name

    subject = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
    OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, "pull-requests.md"),
      "> [#{stamp}] [ agent: #{name}   status: Completed, round 1 (approved) ]")
  end

  it "fetches the diff once and hands every reviewer the same packet" do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:     OpenLanes::Agents::Registry.new.only(*reviewers),
      isolation:  :shared,
      jobs:       3,
      state:,
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false),
      sleeper:    ->(_) {}).call
    # One packet means one nonce, drawn once for the round.
    nonces = prompts.first(3).map { it[/nonce="([0-9a-f]+)"/, 1] }
    aggregate_failures do
      expect(github).to have_received(:diff).once
      expect(prompts.size).to be >= 3
      expect(prompts.first(3)).to all(include("+added line"))
      expect(nonces).to all(match(/\A[0-9a-f]+\z/))
      expect(nonces.uniq.size).to eq(1)
    end
  end
end
