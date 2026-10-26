# frozen_string_literal: true

require "json"

# Live mode runs a real agent, so here the agent is a fake: a spawn that
# writes what a good run would write and streams back a meter reading.
# Nothing in this file starts a process.
RSpec.describe OpenLanes::Evals::Live do
  subject(:outcome) { OpenLanes::Evals.run_live(kase, spawn:, trace_dir:, **options) }

  let(:kase) { OpenLanes::Evals.cases.find { it.id == case_id } }
  let(:case_id) { "research-fast" }
  let(:options) { {} }
  let(:seen) { {} }
  let(:stream) do
    [
      "#{JSON.generate(type: "stream_event",
        event: { type: "message_delta", usage: { input_tokens: 1000, output_tokens: 200 } })}\n",
      "#{JSON.generate(type: "result", is_error: false, result: "done")}\n"
    ]
  end
  let(:exit_status) { instance_double(Process::Status, success?: true) }
  let(:spawn) do
    lambda { |argv, chdir:, **|
      folder = Dir.glob(File.join(chdir, ".plans", "*")).first
      seen.merge!(argv:, folder: File.basename(folder), spec: File.read(File.join(folder, "spec.md")))
      agent_writes.call(chdir, folder)
      child = instance_double(OpenLanes::Execution::Child, pid: 4242, alive?: false, kill: nil, terminate: nil, wait: exit_status)
      allow(child).to receive(:each_chunk) { |&block| stream.each { block.call(it) } }
      child
    }
  end
  let(:agent_writes) do
    lambda { |_root, folder|
      File.write(File.join(folder, "spec.md"), <<~MD)
        # Billing Retries

        ## Research

        ### Reuse in this repo

        - `lib/retry_policy.rb:1` already retries three times with doubling delays from 0.5 s.

        ### Existing components

        - [retriable](https://github.com/kamui/retriable): block retries with backoff; the policy already covers it.

        ### Open questions for spec-writer

        1. What backoff does the billing API ask for, and does it send `Retry-After`?

        > [!NOTE]
        >
        > [2026-09-04 11:31:42 AM PDT] [ agent: researcher   status: Completed, round 1 ]
      MD
    }
  end

  # Every invocation keeps a trace and registers a control file; both belong
  # in a directory the example owns, not in the machine's real trace dir.
  let(:trace_dir) { Dir.mktmpdir("live-traces") }

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(trace_dir)
  end

  it "scores the folder the agent left, renamed to the state its contents justify" do
    expect(outcome.score.failures.map { "#{it.name}: #{it.detail}" }).to eq([])
  end

  it "feeds the meter's reading into the token budget" do
    expect(outcome.score.verdicts.find { it.name.start_with?("tokens") }.detail).to eq("1200 tokens")
  end

  it "hands the agent the plan at the state the fixture names" do
    outcome
    expect(seen[:folder]).to eq("001.00━━⚪━━❯billing-retries")
  end

  it "stamps the requested depth into spec.md, where the profile reads it" do
    outcome
    expect(seen[:spec]).to start_with("---\ndepth: fast\n---\n# Billing Retries")
  end

  it "caps the run at the default token budget" do
    allow(OpenLanes::Execution).to receive(:executor).and_call_original
    outcome

    expect(OpenLanes::Execution).to have_received(:executor).with(hash_including(max_tokens: 300_000))
  end

  it "tells the agent the cap it is held to" do
    outcome
    expect(seen[:argv].join(" ")).to include("Token budget — 300000 tokens")
  end

  it "throws the repository away afterwards" do
    expect(outcome.root).to be_nil
  end

  context "when held to another depth and a tighter cap" do
    let(:kase) { super().at(:deep) }
    let(:options) { { max_tokens: 5000 } }

    it "stamps that depth into spec.md" do
      outcome
      expect(seen[:spec]).to start_with("---\ndepth: deep\n")
    end

    it "fails the deeper bounds a fast run does not meet" do
      expect(outcome.score.failures.map(&:name)).to include(a_string_starting_with("words in spec.md#Research"))
    end

    it "tells the agent the tighter cap" do
      outcome
      expect(seen[:argv].join(" ")).to include("Token budget — 5000 tokens")
    end
  end

  context "when asked to keep the repository" do
    let(:options) { { keep: true } }

    after { FileUtils.rm_rf(outcome.root) }

    it "leaves it on disk for inspection" do
      expect(File.directory?(File.join(outcome.root, ".git"))).to be(true)
    end
  end

  context "with an agent that starts by moving the folder" do
    let(:case_id) { "task-fast" }
    let(:agent_writes) do
      lambda { |root, folder|
        File.write(File.join(root, "lib/greeter.rb"), "module Greeter\n  def self.greet(name) = \"Hello, \#{name}!\"\nend\n")
        File.write(File.join(folder, "plan.md"), "# Plan\n\n## Task\n\n- Changed the typo in lib/greeter.rb.\n")
        File.write(File.join(folder, "pull-requests.md"), <<~MD)
          # Pull Requests

          > [2026-09-04 04:02:40 PM PDT] [ agent: chores-coder   status: Completed, round 1 ]
        MD
      }
    end

    it "hands it the folder under its starts_as name" do
      outcome
      expect(seen[:folder]).to eq("001.00━━🟡━━❯greeting-typo")
    end

    it "scores the diff it made in the repository" do
      expect(outcome.score.failures.map { "#{it.name}: #{it.detail}" }).to eq([])
    end
  end

  context "when the agent removes the plan folder" do
    let(:agent_writes) { ->(_root, folder) { FileUtils.rm_rf(folder) } }

    it "scores the absence rather than crashing" do
      expect(outcome.score.passed?).to be(false)
    end
  end

  it "refuses a case whose agent has gone" do
    expect { described_class.new(kase.with(agent: "nobody")) }.to raise_error(OpenLanes::Evals::Invalid, /nobody/)
  end
end
