# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor, :tree do
  subject(:executor) { described_class.new(root:, spawn:) }

  let(:root) { File.dirname(plans_root) }
  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:agent) { agents.find("yoda-writer") }

  # The seam. Nothing here starts a process; the fake plays back a stream.
  let(:stream) { [] }
  let(:exit_status) { instance_double(Process::Status, success?: true) }
  let(:fake_child) do
    child = instance_double(OpenLanes::Execution::Child, pid: 4242, alive?: false, kill: nil, terminate: nil, wait: exit_status)
    allow(child).to receive(:each_chunk) { |&block| stream.each { |chunk| block.call(chunk) } }
    child
  end
  let(:spawn) { ->(_argv, chdir: nil, **) { fake_child } }

  let!(:built) do
    plans { |t| t.plan "000.00", :new, "a-feature", files: { "spec.md" => spec_body } }
  end

  let(:subject_plan) { OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first }

  # Every invocation keeps a trace and registers a control file. Both belong
  # in a directory the example owns, not in the machine's real trace dir.
  around do |example|
    Dir.mktmpdir("executor-traces") do |dir|
      @traces = dir
      example.run
    end
  end

  before { stub_const("OpenLanes::Execution::Executor::TRACE_DIR", @traces) }

  after { OpenLanes::Execution::Control.reset! }

  describe "choosing the coding agent" do
    let(:writer) { agent.with(phase: "specification") }
    let(:spec_md) { "---\nphases:\n  specification: { adapter: codex, effort: medium }\n---\n#{spec_body}" }
    let!(:built) do
      plans { |t| t.plan "000.00", :new, "a-feature", files: { "spec.md" => spec_md } }
    end
    let(:argv) { executor.invocation(writer, subject_plan) }

    it "hands the plan to the adapter its spec.md names for the agent's phase" do
      expect(argv.first(2)).to eq(%w[codex exec])
    end

    it "translates the effort into that CLI's flag" do
      expect(argv).to include('model_reasoning_effort="medium"')
    end

    it "does not tell the agent a CLI enforces what it cannot" do
      expect([argv.last.include?("cannot withhold them"), argv.last.include?("not merely discouraged")]).to eq([true, false])
    end

    it "names the profile the board shows" do
      expect(executor.profile_for(writer, subject_plan).label).to eq("codex:default")
    end
  end

  describe "starting agents lean" do
    let(:argv) { executor.invocation(agent, subject_plan) }

    it "keeps personal plugins, skills and MCP servers out by default" do
      expect(argv).to include("--strict-mcp-config", "--disable-slash-commands")
    end

    it "lets them in for a run started with --user-config" do
      expect(described_class.new(root:, spawn:, lean: false).invocation(agent, subject_plan))
        .not_to include("--disable-slash-commands")
    end
  end

  describe "#invocation" do
    let(:argv) { executor.invocation(agent, subject_plan) }

    it "withholds the tools that would let an agent reach off the machine" do
      expect(denied(agent)).to include(*described_class::DENIED_TOOLS)
    end

    it "passes through the tools the agent's definition allows" do
      expect(argv.each_cons(2).to_a).to include(["--allowedTools", agent.allowed_tools.join(",")])
    end

    it "scopes the agent to the repository it is working in" do
      expect(argv.each_cons(2).to_a).to include(["--add-dir", root])
    end

    it "tells the agent which plan it has, and what is wrong with it" do
      expect(argv.join(" ")).to include("000.00").and include(subject_plan.feature.path)
    end

    # A prompt is a request and a flag is a guarantee, so the agent gets both:
    # told what it may not do, and prevented from doing it.
    it "states the boundary in the prompt as well as enforcing it in flags" do
      expect(argv.join(" ")).to include("withheld from you, not merely discouraged", "gh pr merge")
    end

    it "appends operator instructions when the run supplied them" do
      steered = described_class.new(root:, spawn:, instructions: "Prefer the parser refactor")
                               .invocation(agent, subject_plan)

      expect(steered[2]).to include("Operator instructions", "Prefer the parser refactor")
    end

    it "adds no operator section when none were supplied" do
      expect(argv[2]).not_to include("Operator instructions")
    end

    it "runs the model the agent's frontmatter declares" do
      expect(argv.each_cons(2).to_a).to include(["--model", "sonnet"])
    end

    # The same precedence every flag here follows: typed beats declared.
    it "lets --model override the agent's own declaration" do
      overridden = described_class.new(root:, spawn:, model: "opus").invocation(agent, subject_plan)

      expect(overridden.each_cons(2).to_a).to include(["--model", "opus"])
      expect(overridden.join(" ")).not_to include("sonnet")
    end

    it "states the token budget in the prompt when one is set" do
      metered = described_class.new(root:, spawn:, max_tokens: 50_000).invocation(agent, subject_plan)

      expect(metered[2]).to include("Token budget — 50000 tokens, enforced")
    end

    it "mentions no budget and no control file when neither exists" do
      expect(argv[2]).not_to include("Token budget", "Control file")
    end

    # Two agents on one plan are two processes. Naming the partner and the
    # exact commands is what replaced guessing the partner's session from
    # every Claude session on the machine.
    it "names the partner and the mailbox commands for an agent that has one" do
      luke = agents.find("luke-backend")
      rey = agents.find("rey-frontend")
      paired = executor.invocation(luke, subject_plan, partners: [rey])[2]

      expect(paired).to include(
        "## Mailbox",
        "Your partner on this plan is `rey-frontend`",
        "kept in the\nplan's `state.json`",
        "openlanes mail read --dir \"#{plans_root}\" --plan 000.00 --for luke-backend",
        "openlanes mail send --dir \"#{plans_root}\" --plan 000.00 --from luke-backend --to rey-frontend"
      )
    end

    # Delivery says nothing about reading; only the reader can, so the
    # prompt asks for the ack right after the read (plan 003, B5).
    it "asks the reader to ack each message it reads" do
      paired = executor.invocation(agents.find("luke-backend"), subject_plan, partners: [agents.find("rey-frontend")])[2]

      expect(paired).to include("openlanes mail ack --dir \"#{plans_root}\" --plan 000.00 --for luke-backend N")
    end

    # `alock` signs a lock with the process fingerprint, which every sub-agent
    # of one `claude` shares, so the prompt names the holder explicitly.
    it "tells the agent to claim files with alock, under its own name" do
      prompt = executor.invocation(agents.find("luke-backend"), subject_plan)[2]

      expect(prompt).to include("AGENT_ID=luke-backend alock acquire", "AGENT_ID=luke-backend alock release-all")
      expect(prompt).not_to include("agent-lock.sh")
    end

    it "adds no mailbox section for an agent working a plan alone" do
      expect(argv[2]).not_to include("Mailbox")
    end

    # The mailbox is the channel. An implementer still holding the
    # session-to-session tools would be told two ways to reach its partner,
    # and the one that guesses is the one that wastes the round.
    it "hands no agent the session-to-session messaging tools" do
      expect(agents.all.flat_map(&:allowed_tools)).not_to include("SendMessage", "ListAgents")
    end
  end

  describe "the clock" do
    it "takes the tighter of the agent's own budget and --timeout" do
      leah = agents.find("leah-researcher") # 1200 in frontmatter
      aggregate_failures do
        expect(described_class.new(root:, spawn:, timeout: 900).timeout_for(leah)).to eq(900)
        expect(described_class.new(root:, spawn:, timeout: 1800).timeout_for(leah)).to eq(1200)
      end
    end

    it "lets an agent's own clock stand when nobody passed --timeout" do
      leah = agents.find("leah-researcher") # 1200 in frontmatter
      expect(described_class.new(root:, spawn:).timeout_for(leah)).to eq(1200)
    end

    it "falls back to the default only for an agent that declares no clock of its own" do
      clockless = agent.with(timeout: nil)
      expect(described_class.new(root:, spawn:).timeout_for(clockless)).to eq(described_class::DEFAULT_TIMEOUT)
    end

    it "does not hand a timeout to the process; the clock is advisory" do
      # A flag, not the word: the checkout's own path may say "timeout".
      expect(executor.invocation(agent, subject_plan).grep(/\A-.*timeout/)).to be_empty
    end
  end

  describe "the argv" do
    it "starts every agent with --brief so it can talk back" do
      expect(executor.invocation(agent, subject_plan)).to include("--brief")
    end

    it "passes the agent's effort when it declares one" do
      expect(executor.invocation(agent, subject_plan).each_cons(2).to_a).to include(["--effort", "medium"])
    end

    it "passes no effort for an agent that declares none" do
      argv = executor.invocation(agent.with(effort: nil), subject_plan)
      expect(argv).not_to include("--effort")
    end
  end

  describe "the ledger section" do
    let(:prompt) { executor.invocation(agent, subject_plan, round: 2, successor: "palpatine-planner")[2] }

    let(:sign) do
      "openlanes state sign --dir \"#{plans_root}\" --plan 000.00 --agent yoda-writer --round 2"
    end

    it "tells the agent the exact commands to sign with, under its own name, round and successor" do
      aggregate_failures do
        expect(prompt).to include("#{sign} --status Started")
        expect(prompt).to include("#{sign} --status Completed --next palpatine-planner")
      end
    end

    it "says how a parenthesised note in the agent's instructions maps onto the command" do
      expect(prompt).to include("--note technical")
    end

    it "tells the agent never to edit state.json by hand" do
      expect(prompt).to include("Never\nedit `state.json` by hand")
    end

    it "explains the warnings the control file will carry" do
      expect(prompt).to include("WARN:", "WRAP_UP:", "STOP")
    end

    # What makes a restart after ctrl-c idempotent: a resume record on the
    # way out, and every agent reading it on the way in.
    context "with a control file" do
      let(:controlled) { executor.invocation(agent, subject_plan, control: "/tmp/control-000.00-yoda-writer")[2] }

      it "asks an interrupted agent for a resume record, and every agent to read one first" do
        expect(controlled).to include("INTERRUPT",
          "Interrupted",
          "openlanes state resume --dir \"#{plans_root}\" --plan 000.00 --agent yoda-writer --round 1",
          "\"last-known-state\".\"yoda-writer\"",
          "mail read")
      end

      it "no longer asks for a RESUME mail to itself" do
        expect(controlled).not_to include("--from yoda-writer --to yoda-writer")
      end
    end
  end

  describe "#call with a handle" do
    let(:handle) { described_class::Handle.new }

    it "exposes the child and the clock to the caller while the agent runs" do
      seen = nil
      allow(fake_child).to receive(:each_chunk) { seen = [handle.pid, handle.remaining.class] }
      executor.call(agent, subject_plan, handle:)
      expect(seen).to eq([4242, Integer])
    end

    it "reports a key kill as such, and does not count it as success" do
      allow(fake_child).to receive(:each_chunk) { handle.kill!(grace: 0) }
      allow(fake_child).to receive(:alive?).and_return(true)
      result = executor.call(agent, subject_plan, handle:)
      aggregate_failures do
        expect(result.killed).to eq(:key)
        expect(result.ok).to be(false)
        expect(fake_child).to have_received(:terminate)
      end
    end

    it "writes STOP before it kills" do
      control_text = nil
      allow(fake_child).to receive(:each_chunk) {
        handle.kill!(grace: 0)
        control_text = File.read(handle.control)
      }
      executor.call(agent, subject_plan, handle:)
      expect(control_text.strip).to eq("STOP")
    end
  end

  # The autonomy boundary is closed by default and opened per agent, in the
  # agent's own file. A researcher whose whole job is reading the internet was
  # otherwise handed --disallowedTools WebFetch,WebSearch on every invocation,
  # and duly ran, found nothing, and reported success.
  def agent_with(network: false, may: [])
    OpenLanes::Agents::Agent.new(
      name:          "x",
      description:   "",
      handles:       [:new],
      advances_to:   :planned,
      model:         nil,
      allowed_tools: [],
      may:,
      network:,
      timeout:       nil,
      prompt:        "do it",
      path:          "x.md"
    )
  end

  def denied(agent)
    described_class.new(root:, spawn:).invocation(agent, subject_plan)
                   .each_cons(2).find { |flag, _| flag == "--disallowedTools" }&.last.to_s.split(",")
  end

  describe ".foreign_credentials" do
    it "names the credentials an agent would authenticate with instead of the login" do
      expect(described_class.foreign_credentials({ "ANTHROPIC_API_KEY" => "sk-ant-x" })).to eq(["ANTHROPIC_API_KEY"])
    end

    it "ignores one that is set to nothing, which is how a shell unsets it in practice" do
      expect(described_class.foreign_credentials({ "ANTHROPIC_API_KEY" => "  " })).to be_empty
    end
  end

  describe "the network boundary" do
    it "denies the web to an agent that did not ask for it" do
      expect(denied(agent_with(network: false))).to include("WebFetch", "WebSearch")
    end

    it "grants it to one that did" do
      expect(denied(agent_with(network: true))).not_to include("WebFetch", "WebSearch")
    end

    it "defaults to closed when the definition says nothing" do
      expect(agent_with.network).to be(false)
    end

    # Opening the network does not open anything else.
    it "leaves the command boundary alone either way" do
      expect(denied(agent_with(network: true))).to include("Bash(git push:*)")
    end
  end

  # This list spent a while as a regular expression nothing referenced — a
  # guard in the shape of a constant. `gh pr review` was reachable by every
  # agent, and granted to none.
  describe "the command boundary" do
    it "withholds every forbidden command from an agent that asked for nothing" do
      expect(denied(agent_with)).to include(*described_class::FORBIDDEN_COMMANDS.map { |c| "Bash(#{c}:*)" })
    end

    it "lifts exactly what an agent's definition asks for" do
      argv = denied(agent_with(may: ["gh pr review"]))

      aggregate_failures do
        expect(argv).not_to include("Bash(gh pr review:*)")
        expect(argv).to include("Bash(gh pr comment:*)")
      end
    end

    # The line between approving and merging. An approval is reversible,
    # visible and attributable; a merge changes a branch everyone builds on.
    it "refuses to lift a merge or a push, however the definition is written" do
      argv = denied(agent_with(may: ["gh pr merge", "git push", "gh pr review"]))

      aggregate_failures do
        expect(argv).to include("Bash(gh pr merge:*)", "Bash(git push:*)")
        expect(argv).not_to include("Bash(gh pr review:*)")
      end
    end

    it "tells the agent what it has been granted, not only what it has lost" do
      argv = described_class.new(root:, spawn:).invocation(agent_with(may: ["gh pr review"]), subject_plan)

      expect(argv.join(" ")).to include("You may run these, which most agents may not", "gh pr review")
    end

    it "says nothing about grants to an agent that has none" do
      argv = described_class.new(root:, spawn:).invocation(agent_with, subject_plan)

      expect(argv.join(" ")).not_to include("which most agents may not")
    end
  end

  describe "hansolo-reviewer, as the repository actually defines him" do
    let(:hansolo) { OpenLanes::Agents::Registry.new(dir: "agents").all.find { |a| a.name == "hansolo-reviewer" } }

    it "may review, which is the point of him" do
      expect(denied(hansolo)).not_to include("Bash(gh pr review:*)")
    end

    it "may not merge, which is the line" do
      expect(denied(hansolo)).to include("Bash(gh pr merge:*)", "Bash(git push:*)")
    end
  end

  # `claude -p` says nothing until it is finished, so a fifteen minute
  # invocation and a hung one look identical. Asked for the streaming format it
  # reports each tool call as it makes it, and this is what reads them.
  describe "streaming what the agent is doing" do
    subject(:streaming) { described_class.new(root:, spawn:, trace_dir: @traces) }

    let(:seen) { [] }

    def event(hash) = "#{JSON.generate(hash)}\n"

    def tool(name, input) = event(type: "assistant", message: { content: [{ type: "tool_use", name:, input: }] })

    it "asks claude for the streaming format, which needs --verbose to work at all" do
      expect(streaming.invocation(agent, subject_plan).each_cons(2).to_a).to include(["--output-format", "stream-json"]).and include(["stream-json", "--verbose"])
    end

    # A tool name is a noun and says nothing on its own. The spinner has room
    # for a phrase, so it gets one.
    it "hands each tool call to whoever is drawing the progress, as something being done" do
      stream << tool("Read", { file_path: "/repo/spec.md" })
      streaming.call(agent, subject_plan) { |progress| seen << progress.activity }

      expect(seen).to eq(["reading spec.md"])
    end

    # Without it the stream reports a placeholder for what the model
    # generated — 2 for a four-thousand-token answer — and the counter on the
    # spinner line reads zero for the whole run.
    it "asks for partial messages, which is the only place a settled token count arrives" do
      expect(streaming.invocation(agent, subject_plan)).to include("--include-partial-messages")
    end

    it "reports what the invocation spent, not only whether it worked" do
      stream << event(type: "stream_event",
        event: { type: "message_delta", usage: { input_tokens: 2, cache_creation_input_tokens: 100,
                                               cache_read_input_tokens: 900, output_tokens: 40 } })

      expect(streaming.call(agent, subject_plan)).to have_attributes(up: 1002, down: 40, cached: 900, fresh: 142)
    end

    # The prompt states the budget so the agent can finish inside it; this is
    # the half that makes the statement true. The kill goes through the same
    # handle a keypress uses, so the child is signalled, not merely abandoned.
    describe "the token budget, enforced" do
      subject(:metered) { described_class.new(root:, spawn:, trace_dir: @traces, max_tokens: 100) }

      it "aborts the invocation once the meter crosses the budget" do
        allow(fake_child).to receive(:alive?).and_return(true)
        stream << event(type: "stream_event",
          event: { type: "message_delta", usage: { input_tokens: 90, output_tokens: 40 } })

        result = metered.call(agent, subject_plan)

        aggregate_failures do
          expect(result).to have_attributes(ok: false, killed: :budget, up: 90, down: 40)
          expect(result.note).to include("token budget of 100 exceeded")
          expect(fake_child).to have_received(:terminate)
        end
      end

      it "lets an invocation inside the budget finish untouched" do
        stream << event(type: "stream_event",
          event: { type: "message_delta", usage: { input_tokens: 50, output_tokens: 40 } })
        stream << event(type: "result", is_error: false, result: "done")

        expect(metered.call(agent, subject_plan).ok).to be(true)
      end

      # Every turn re-reads the whole context from cache. Counted, those reads
      # end a live eval after ten turns of a 30k-token context.
      context "when only fresh tokens count" do
        subject(:metered) { described_class.new(root:, spawn:, trace_dir: @traces, max_tokens: 100, fresh_budget: true) }

        it "lets cache reads past the budget" do
          stream << event(type: "stream_event",
            event: { type: "message_delta", usage: { input_tokens: 10, cache_read_input_tokens: 5000, output_tokens: 40 } })
          stream << event(type: "result", is_error: false, result: "done")

          expect(metered.call(agent, subject_plan)).to have_attributes(ok: true, fresh: 50)
        end

        it "says so in the prompt" do
          expect(metered.invocation(agent, subject_plan)[2]).to include("cache reads are free")
        end
      end
    end

    # The keyboard's side of the bargain lives in {Control}; this is the
    # executor's: a control file per invocation, named in the prompt, released
    # after, and a hard stop once q's grace period is spent. Every invocation
    # gets one, because the clock writes into it whether or not anyone is at
    # the keys.
    describe "the control file" do
      let(:prompts) { [] }
      let(:spawn) do
        ->(argv, chdir: nil, **) {
          prompts << argv[2]
          fake_child
        }
      end

      it "registers one per invocation, names it in the prompt, and releases it after" do
        streaming.call(agent, subject_plan)

        expect(prompts.first).to include("Control file", "control-000.00-yoda-writer")
        expect(Dir.children(@traces).grep(/^control-/)).to be_empty
      end

      it "aborts whatever is still running once the grace period after q is spent" do
        allow(OpenLanes::Execution::Control).to receive(:overdue?).and_return(true)
        allow(fake_child).to receive(:alive?).and_return(true)
        stream << event(type: "stream_event",
          event: { type: "message_delta", usage: { input_tokens: 1, output_tokens: 1 } })

        result = streaming.call(agent, subject_plan)

        aggregate_failures do
          expect(result).to have_attributes(ok: false, killed: :quit)
          expect(result.note).to include("after q")
          expect(fake_child).to have_received(:terminate)
        end
      end
    end

    # A run that burned two hundred thousand tokens before timing out is a
    # different fact from one that failed to authenticate and spent nothing.
    it "reports what a failed invocation spent too" do
      stream << event(type: "stream_event",
        event: { type: "message_delta", usage: { input_tokens: 500, output_tokens: 7 } })
      stream << event(type: "result", is_error: true, result: "it went wrong")

      expect(streaming.call(agent, subject_plan)).to have_attributes(ok: false, up: 500, down: 7)
    end

    it "counts the sub-agents an agent spawned" do
      stream << event(type: "system", subtype: "task_started", task_id: "t1", tool_use_id: "toolu_1")
      stream << event(type: "system",
        subtype: "task_notification",
        task_id: "t1",
        usage: { total_tokens: 34_116 })

      expect(streaming.call(agent, subject_plan)).to have_attributes(subagents: 1, delegated: 34_116)
    end

    it "runs perfectly well with nothing to report to" do
      stream << tool("Read", {})

      expect(streaming.call(agent, subject_plan).ok).to be(true)
    end

    it "says how much work the agent did, rather than only that it finished" do
      stream.push(tool("Read", {}), tool("Edit", {}))

      expect(streaming.call(agent, subject_plan).note).to eq("completed - 2 tool calls")
    end

    it "keeps the raw stream, so a run that went wrong can be read back" do
      stream << event(type: "result", subtype: "success", result: "Folded B3.")
      streaming.call(agent, subject_plan)

      trace = Dir.children(@traces).grep(/\.ndjson\z/).first
      expect(File.read(File.join(@traces, trace))).to include("Folded B3.")
    end

    # Two agents run at once under `run -j`, and more than one openlanes
    # may be driving the same checkout.
    it "gives each invocation its own trace rather than one they share" do
      2.times { streaming.call(agent, subject_plan) }

      expect(Dir.children(@traces).grep(/\.ndjson\z/).size).to eq(2)
    end

    # `claude` reports failure two ways, and the readable one wins. A crash
    # that got far enough emits a `result` event; one that died on startup
    # printed prose on stdout; one that printed nothing at all leaves only
    # the exit status to quote. Each used to be reported as the least readable
    # of the three: the shell-escaped prompt, ten times per round.
    describe "when claude exits non-zero" do
      let(:exit_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }

      it "prefers the stream's own result event over anything else" do
        stream << event(type: "result", is_error: true, result: "model refused the tool")

        expect(streaming.call(agent, subject_plan)).to have_attributes(
          ok: false, note: a_string_including("claude exited 1: model refused the tool")
        )
      end

      it "falls back to what claude printed before dying, when no event arrived" do
        stream << "Failed to authenticate. 401 API key is invalid.\n"

        expect(streaming.call(agent, subject_plan).note).to include("exited 1: Failed to authenticate. 401 API key is invalid.")
      end

      it "says so plainly when the agent exited without explaining itself" do
        expect(streaming.call(agent, subject_plan).note).to include("exited 1: said nothing")
      end

      it "still names the trace, since a failure is when it is wanted" do
        expect(streaming.call(agent, subject_plan).note).to include(".ndjson")
      end
    end
  end

  # The after-check half of the boundary. A prompt is a request; this is the
  # guarantee — an agent that committed anyway is reported as a failure, not
  # trusted because it said "completed".
  describe "the after-check on HEAD" do
    subject(:streaming) { described_class.new(root:, spawn:, trace_dir: @traces) }

    let(:stream) { [%({"type":"result","subtype":"success","result":"done"}\n)] }

    before do
      system("git", "-C", root, "init", "-q", "--initial-branch=main", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "config", "user.email", "alan.turing@manchester.edu")
      system("git", "-C", root, "config", "user.name", "Alan Turing")
      system("git", "-C", root, "add", "-A", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "commit", "-qm", "initial", out: File::NULL, err: File::NULL)
    end

    it "passes an invocation that left HEAD alone" do
      expect(streaming.call(agent, subject_plan).ok).to be(true)
    end

    it "reports an invocation that committed, however successful it claims to be" do
      allow(fake_child).to receive(:each_chunk) do
        File.write(File.join(root, "sneaky.txt"), "x")
        system("git", "-C", root, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", root, "commit", "-qm", "agent commit", out: File::NULL, err: File::NULL)
      end

      expect(streaming.call(agent, subject_plan)).to have_attributes(
        ok: false, note: a_string_including("agent committed", "HEAD moved")
      )
    end
  end

  # An agent that does not know its clock cannot pace itself against it, and
  # prose naming a figure goes stale the moment anyone passes `--timeout`. So
  # the number in the prompt is read off the same method that enforces it.
  describe "the time budget, stated in the prompt" do
    def prompt_for(who) = executor.invocation(who, subject_plan).join(" ")

    it "names the seconds the run will actually enforce" do
      expect(prompt_for(agent)).to include("Time budget - #{executor.timeout_for(agent)} seconds")
    end

    it "states the agent's own clock when it is the tighter one, not the default" do
      quick = agent.with(timeout: 120)

      expect(prompt_for(quick)).to include("Time budget - 120 seconds").and include("about 2 minutes")
    end

    it "tells an agent that can fan out to spend its budget concurrently" do
      researcher = agents.find("leah-researcher")
      expect(researcher.allowed_tools).to include("Task")
      expect(prompt_for(researcher)).to include("one wave of concurrent sub-agents")
    end

    it "says nothing about concurrency to an agent without Task" do
      planner = agents.find("palpatine-planner")

      expect(planner.allowed_tools).not_to include("Task")
      expect(prompt_for(planner)).not_to include("concurrent sub-agents")
    end
  end

  # The prompt tells the agent when its folder's name is a lie, because the
  # agent that can fix that is the one being invoked on it.
  describe "the prompt, for a folder whose name is not justified" do
    let!(:built) do
      plans { |t| t.plan "010.00", :approved, "lying", prs: [t.open(5, "still open")] }
    end

    it "names the violation" do
      lying = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
      argv = executor.invocation(agent, lying)

      expect(argv.join(" ")).to include("The folder's name is not currently justified")
    end
  end
end
