# frozen_string_literal: true

# `openlanes run` is the command that spends money and moves folders, so its
# examples divide sharply: the dry run and the refusals use the real executor
# (which shells nothing out when dry), and every real-run example replaces
# {Executor} at its seam so the suite never invokes `claude`.
#
# Everything runs `--isolation shared`: the fixture tree is a bare temp
# directory, not a git repository, and shared mode is the one that needs no
# git — which is itself the first property under test.
RSpec.describe OpenLanes::CLI::Run, :tree do
  subject(:command) { described_class.new }

  # The live board publishes to a store kept in this process, never to the
  # Redis a developer's machine happens to run.
  let(:live_store) { OpenLanes::Live.memory_store }

  # The control room is a process of its own; the suite never spawns it, and
  # never opens a browser.
  let(:web) do
    instance_double(OpenLanes::Web::Launcher, ready?: true, port: 11_000, url: "http://127.0.0.1:11000", log: "/tmp/web.log", stop: nil)
  end

  # STDERR as it was written, before strip_ansi: what a terminal received.
  let(:raw) { {} }

  before do
    allow(OpenLanes::Engine::Runner).to receive(:new).and_wrap_original do |original, **keywords|
      original.call(**keywords, sleeper: ->(_) {})
    end
    allow(OpenLanes::Live).to receive(:connect).and_return(live_store)
    allow(web).to receive(:start).and_return(web)
    allow(OpenLanes::Web).to receive(:launcher).and_return(web)
    allow(OpenLanes::Web).to receive(:open)
  end

  # The loop sleeps a second between ticks. Every example hands the runner
  # the no-op sleeper runner_spec uses, or each real-run example is two
  # seconds of waiting for nothing. The same spy serves the --rounds examples.

  # A `.openlanes.yml` at the example's project root, with the suite moved there
  # the way {OpenLanes::CLI::Base} moves a real command.
  def openlanes_yml(text)
    root = File.dirname(plans_root)
    File.write(File.join(root, ".openlanes.yml"), text)
    Dir.chdir(root)
  end

  # What dry-cli hands the command for +argv+: typed flags over `.openlanes.yml`
  # over the built-in defaults, as a real run sees them.
  def typed(*argv)
    Dry::CLI::Parser.call(described_class, argv, "openlanes run").arguments
                    .except(:dir, :isolation).merge(dry_run: false, until_settled: true)
  end

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      # The log always lands in the example's own temp dir, never in the
      # shared system one where parallel suites would interleave into it.
      # --until-settled, because a run with its control room up otherwise
      # stays until it is stopped; "the control room" says what it does.
      command.call(dir: plans_root,
        isolation: "shared",
        log: File.join(plans_root, "..", "progress.log"),
        dry_run: true,
        until_settled: true,
**)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    raw[:err] = err.string
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  # 🟡 Building is the cheapest *stable* assignable state: it sits inside a
  # {StateMachine::FAMILIES} group, so the resync each round runs cannot move
  # it on its own. A ⭐ folder would not do — its contents already best-fit
  # 🟡, so the first round's resync advances it before any agent has run,
  # and every "nothing happened" assertion below would be false.
  def building_plan(ordinal = "001.00", slug = "tax-rule-dsl")
    plans { |t| t.plan(ordinal, :building, slug, files: { "spec.md" => spec_body, "plan.md" => "# Plan", "plan-frontend.md" => "## F1" }) }
  end

  # The real-run seam. The block sees the subject and the agent before
  # answering, so an example can have "the agent" actually change the folder
  # and sign its own ledger. It answers `[ok, note]`, wrapped here into the
  # {OpenLanes::Execution::Executor::Result} the dispatcher reads.
  def with_executor(&decide)
    executor = instance_double(OpenLanes::Execution::Executor)
    allow(executor).to receive(:call) do |agent, subject, **|
      ok, note = decide ? decide.call(subject, agent) : [true, "completed"]
      OpenLanes::Execution::Executor::Result.new(ok:, note:, up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
    end
    allow(OpenLanes::Execution::Executor).to receive(:new).and_return(executor)
    executor
  end

  describe "the worktree default against a tree with no git" do
    it "refuses with the alternative spelled out, rather than corrupting later" do
      building_plan
      out = CapturedStream.new
      err = CapturedStream.new
      status = 0

      original_out, original_err = $stdout, $stderr
      $stdout, $stderr = out, err
      begin
        command.call(dir: plans_root, dry_run: true)
      rescue SystemExit => e
        status = e.status
      ensure
        $stdout, $stderr = original_out, original_err
      end

      expect(unwrapped(strip_ansi(err.string))).to include("not a git repository", "--isolation shared")
      expect(status).to eq(66)
    end
  end

  describe "--timeout and the config file" do
    before { building_plan }

    it "hands --timeout to the executor" do
      with_executor
      run(dry_run: false, timeout: "1800")

      expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(timeout: 1800))
    end

    it "reads the default timeout from .openlanes.yml" do
      openlanes_yml("commands:\n  run:\n    timeout: 2400\n")
      with_executor
      run(**typed)

      expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(timeout: 2400))
    end

    it "lets the typed flag beat the config file" do
      openlanes_yml("commands:\n  run:\n    timeout: 2400\n")
      with_executor
      run(**typed("--timeout", "600"))

      expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(timeout: 600))
    end

    # The executor falls back to 900 only for an agent with no clock of its
    # own; a flag defaulting to 900 here silently cut every longer agent.
    it "leaves each agent to its own clock when neither names one" do
      with_executor
      run(dry_run: false)

      expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(timeout: nil))
    end

    it "refuses an unreadable config file rather than silently ignoring it" do
      openlanes_yml("commands: [")
      _out, err, status = run

      expect(unwrapped(err)).to include(".openlanes.yml", "not valid YAML")
      expect(status).to eq(65)
    end

    it "refuses an option run does not take" do
      openlanes_yml("commands:\n  run:\n    timeuot: 60\n")
      _out, err, status = run

      expect([unwrapped(err), status]).to match([include("commands.run.timeuot", "no such option"), 65])
    end

    it "takes jobs from the top of .openlanes.yml" do
      openlanes_yml("jobs: 3\n")

      expect(typed[:jobs]).to eq(3)
    end
  end

  describe "--rounds" do
    before { building_plan }

    it "reaches the runner as a cap on every agent's own rounds" do
      run(rounds: 1)

      expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_including(rounds: 1))
    end

    it "leaves each agent to its own count when none is given" do
      run

      expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_including(rounds: nil))
    end
  end

  describe "a dry run" do
    before { building_plan }

    it "prints which agent would take which plan, and invokes none" do
      out, err, status = run

      expect(out).to include("001.00  luke-backend  [R:1]  no change  dry run - would invoke luke-backend")
      expect(unwrapped(err)).to include("Dry run — no agent was invoked", "without --dry-run")
      expect(status).to eq(0)
    end

    # Tabs put each column on the next multiple of eight, so "yoda-writer"
    # being one character shorter than "luke-backend" moved its round and
    # mark a whole stop left of the rows above it.
    describe "the attempts list, with agents whose names are different lengths" do
      subject(:columns) { lines.map { |line| line.index("[R:") } }

      let(:lines) { run.first.lines.grep(/\[R:/) }

      before { plans { |t| t.plan("002.00", :researched, "second-plan", files: { "spec.md" => spec_body }) } }

      it("lists an attempt per agent") { expect(lines.size).to be > 1 }
      it("puts every round in the same column") { expect(columns.uniq.size).to eq(1) }
    end

    # Unparseable frontmatter routes as lane: full with every override
    # dropped; the run has to say so before it assigns anyone.
    it "names a plan whose spec.md frontmatter does not parse" do
      plans { |t| t.plan("002.00", :new, "bad-yaml", files: { "spec.md" => "---\nlane: quick\nhow-to-verify:\n  - `rg x`\n---\n# Bad\n" }) }
      _out, err, = run

      expect(unwrapped(err)).to include("frontmatter ignored", "002.00", "not valid YAML")
    end

    it "spends nothing, so it prints no bill" do
      out, = run

      expect(out).not_to include("tokens")
    end

    # The per-round resync used to run with dry_run: false even here, so a
    # "dry" run renamed a ⭐ folder whose plan.md already existed. A preview
    # that moves folders is not a preview.
    it "renames nothing, even a folder the resync would promote" do
      plans { |t| t.plan("002.00", :planned, "stays-put", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }) }
      run

      expect(Dir.children(plans_root).grep(/stays-put/)).to eq(["002.00━━⭐━━❯stays-put"])
    end

    it "says where the log is going before the loop starts" do
      _out, err, = run

      expect(unwrapped(err)).to include("Log:", "progress.log")
    end
  end

  describe "--agent" do
    before { building_plan }

    it "narrows the round to the one agent named, leaving other states unassigned" do
      plans { |t| t.plan("003.00", :new, "raw-idea", files: { "spec.md" => spec_body }) }
      out, = run(agent: "luke-backend")

      expect(out).to include("luke-backend")
      expect(out).not_to include("leah-researcher")
    end

    it "refuses a name nobody answers to, listing who does" do
      _out, err, status = run(agent: "obi-wan")

      expect(unwrapped(err)).to include("No agent called obi-wan", "luke-backend")
      expect(status).to eq(65)
    end

    # The bug this kills: `--agent luthen-rael-planner --plan NNN` on a plan in
    # a state luthen-rael does not handle produced an empty round, a green box
    # and exit 0 — a silent no-op wearing a success. The pairing that cannot
    # happen is now refused up front, naming who would take the plan.
    it "refuses an agent that handles no in-scope plan's state, naming who does" do
      _out, err, status = run(agent: "leah-researcher")

      expect(unwrapped(err)).to include("leah-researcher handles", "🟡 Building", "luke-backend and rey-frontend take it")
      expect(status).to eq(65)
    end
  end

  describe "--max-tokens" do
    before { building_plan }

    it "hands the budget to the executor" do
      with_executor
      run(dry_run: false, max_tokens: "50000")

      expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(max_tokens: 50_000))
    end

    it "reads a default budget from the config file" do
      openlanes_yml("commands:\n  run:\n    max_tokens: 80000\n")
      with_executor
      run(**typed)

      expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(max_tokens: 80_000))
    end

    it "meters nothing when neither names a budget" do
      with_executor
      run(dry_run: false)

      expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(max_tokens: nil))
    end
  end

  describe "--prompt" do
    before { building_plan }

    it "hands the extra instructions to the executor, alongside --agent" do
      with_executor
      run(dry_run: false, agent: "luke-backend", prompt: "Focus on the parser")

      expect(OpenLanes::Execution::Executor).to have_received(:new)
        .with(hash_including(instructions: "Focus on the parser"))
    end

    context "when a short --prompt names an existing file" do
      before do
        with_executor
        File.write(File.join(plans_root, "steer.txt"), "Focus on the parser, from a file")
        Dir.chdir(plans_root) { run(dry_run: false, agent: "luke-backend", prompt: "steer.txt") }
      end

      it "reads the instructions from the file" do
        expect(OpenLanes::Execution::Executor).to have_received(:new)
          .with(hash_including(instructions: "Focus on the parser, from a file"))
      end
    end

    context "when a --prompt of 80 characters or more names an existing file" do
      let(:long_path) { File.join(plans_root, "#{"x" * 80}.txt") }

      before do
        with_executor
        File.write(long_path, "from the file")
        run(dry_run: false, agent: "luke-backend", prompt: long_path)
      end

      it "takes the prompt as the text" do
        expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(instructions: long_path))
      end
    end

    # Without the restriction the steer would reach every agent in the round,
    # which is never what a sentence aimed at one specialist means.
    it "refuses --prompt without --agent" do
      _out, err, status = run(prompt: "Focus on the parser")

      expect(unwrapped(err)).to include("--prompt only works with --agent")
      expect(status).to eq(64)
    end
  end

  describe "--model" do
    before { building_plan }

    it "hands the override to the executor" do
      with_executor
      run(dry_run: false, model: "opus")

      expect(OpenLanes::Execution::Executor).to have_received(:new).with(hash_including(model: "opus"))
    end
  end

  describe "--skip" do
    before { building_plan }

    it "never assigns the skipped agent, so its plans simply wait" do
      out, _err, status = run(skip: "luke-backend")

      expect(out).not_to include("luke-backend")
      expect(status).to eq(0)
    end

    it "leaves the rest of the round to everyone else" do
      plans { |t| t.plan("003.00", :new, "raw-idea", files: { "spec.md" => spec_body }) }
      out, = run(skip: "luke-backend")

      expect(out).to include("leah-researcher")
      expect(out).not_to include("luke-backend")
    end

    # A typo'd skip silently skipping nobody is the same failure --plan
    # refuses for numbers.
    it "refuses a name nobody answers to" do
      _out, err, status = run(skip: "obi-wan")

      expect(unwrapped(err)).to include("No agent called obi-wan", "luke-backend")
      expect(status).to eq(65)
    end

    it "refuses --agent and --skip naming the same agent" do
      _out, err, status = run(agent: "luke-backend", skip: "luke-backend")

      expect(unwrapped(err)).to include("contradict")
      expect(status).to eq(64)
    end
  end

  describe "--plan" do
    before do
      building_plan
      building_plan("002.00", "schedule-k1")
    end

    it "runs exactly the plans named and no others" do
      out, = run(plan: "002")

      expect(out).to include("002.00")
      expect(out).not_to include("001.00\t")
    end

    # A typo'd number silently running the whole tree is the failure scoping
    # exists to prevent, so an unknown one stops the run outright.
    it "refuses a number the tree does not hold" do
      _out, err, status = run(plan: "002,009")

      expect(unwrapped(err)).to include("No plan 009", "001.00, 002.00")
      expect(status).to eq(66)
    end
  end

  describe "without --dry-run" do
    before { building_plan }

    # The stub answers ok and signs nothing, so the dispatcher looks for the
    # work on disk, finds no pull request to justify 🟢, and marks the attempt
    # Interrupted. Both of the pair get their turn at 🟡, and with nobody to
    # answer, each is granted one more round on its own (E1) before it has
    # no rounds left: one plan, four invocations, four failures.
    it "reports each attempt, prints the bill, and exits non-zero when nothing was signed" do
      with_executor
      out, err, status = run(dry_run: false, rounds: 1)

      expect(out).to include("001.00  luke-backend")
      # A committed run spent something, so the tally belongs with the
      # attempts it bills for, on STDOUT, where a redirected run keeps it.
      expect(out).to include("4 invocations")
      expect(unwrapped(err)).to include("0 advanced", "4 failed")
      expect(status).to eq(1)
    end

    it "writes its progress to log/development.log under the project when --log names none" do
      with_executor
      _out, err, _status = run(dry_run: false, rounds: 1, log: nil)
      log = File.join(File.dirname(plans_root), "log", "development.log")
      aggregate_failures do
        expect(err.gsub(/[\s│]+/, "")).to include("Log:#{log}") # the box wraps long paths
        written = File.read(log)
        expect(written).to include("engine -- run starting", "engine -- started", 'agent: "luke-backend"')
        expect(written).to match(/ W \[.*engine -- run finished -- \{attempts: \d+, failed: \d+/)
      end
    end

    it "refuses a log level it does not know, before anything runs" do
      _out, err, status = run(dry_run: false, rounds: 1, log_level: "loud")

      aggregate_failures do
        expect(status).to eq(64)
        expect(err).to include("--log-level loud: use one of debug, info, warn, error, fatal")
      end
    end

    it "writes JSON, one object per line, under --log-format json" do
      with_executor
      run(dry_run: false, rounds: 1, log_format: "json")
      lines = File.readlines(File.join(plans_root, "..", "progress.log")).map { JSON.parse(it) }

      expect(lines).to include(a_hash_including("name" => "engine",
        "message" => "started",
        "payload" => a_hash_including("agent" => "luke-backend")))
    end

    # Narrowed to luke: once he moves the plan to 🟢, hansolo would take it
    # next, sign nothing, and fail the run for a reason this example is not
    # about.
    it "exits zero when the agent signs Completed and the folder moves" do
      with_executor { |subject|
        File.write(File.join(subject.feature.path, "plan-backend.md"), "> [2026-09-04 11:29:20 AM PDT] [ agent: luke-backend   status: Completed, round 1 ]\n")
        File.write(File.join(subject.feature.path, "plan-frontend.md"), "> [2026-09-04 11:29:20 AM PDT] [ agent: rey-frontend   status: Completed, round 1 ]\n")
        File.write(File.join(subject.feature.path, "pull-requests.md"), "| Pull Request Number | Pull Request Name | Status |\n| --: | :-- | --: |\n| 1 | [x](https://github.com/example/repo/pull/1) | Open 🟡 |\n")
        [true, "completed"]
      }
      out, _err, status = run(dry_run: false, agent: "luke-backend")
      expect(out).to include("building -> ready_for_review")
      expect(status).to eq(0)
    end

    # luke `starts_as` 🟡, so a ⭐ folder moves the moment he is dispatched.
    # The stub signs Almost completed rather than Completed: the attempt is
    # then ok without claiming 🟢, and the plan sits at 🟡 where it landed.
    it "shows a plan that actually moved as from -> to" do
      plans { |t| t.plan("002.00", :planned, "moves", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }) }
      with_executor { |subject, agent|
        File.write(File.join(subject.feature.path, agent.ledger.first),
          "> [2026-09-04 11:29:20 AM PDT] [ agent: #{agent.name}   status: Almost completed, round 1 ]\n")
        [true, "paused"]
      }
      out, err, = run(dry_run: false)

      expect(out).to include("planned -> building")
      expect(unwrapped(err)).to include("1 advanced")
    end

    # The terminal is told each event as it happens, one whole line each,
    # with only the fields that line has: never a cursor move, a carriage
    # return, or the log file's empty columns.
    it "says each event on the terminal as one plain, appended line" do
      with_executor
      _out, err, = run(dry_run: false, rounds: 1)

      aggregate_failures do
        expect(err).to match(/^\d\d:\d\d:\d\d  001\.00 🟡  Building  luke-backend r01  started$/)
        expect(err).to match(/^\d\d:\d\d:\d\d  001\.00 🟡  Building  luke-backend r01  failed: /)
        expect(raw[:err]).not_to match(/\r|\e\[/)
        expect(err).not_to include("|        |")
      end
    end

    it "names the state a plan moved to on its finished line" do
      with_executor { |subject|
        File.write(File.join(subject.feature.path, "plan-backend.md"), "> [2026-09-04 11:29:20 AM PDT] [ agent: luke-backend   status: Completed, round 1 ]\n")
        File.write(File.join(subject.feature.path, "pull-requests.md"), "| Pull Request Number | Pull Request Name | Status |\n| --: | :-- | --: |\n| 1 | [x](https://github.com/example/repo/pull/1) | Open 🟡 |\n")
        [true, "completed"]
      }
      _out, err, = run(dry_run: false, agent: "luke-backend")

      expect(err).to match(/luke-backend r01  finished: .* → 🟢  Ready for Review$/)
    end

    it "keeps the terminal silent about events under --quiet, and the log file in its columns" do
      with_executor
      _out, err, = run(dry_run: false, rounds: 1, quiet: true)
      log = File.read(File.join(plans_root, "..", "progress.log"))

      aggregate_failures do
        expect(err).not_to include("started")
        expect(log).to include('agent: "luke-backend", round: "01"')
      end
    end

    it "exits non-zero and names the failure when an agent fails" do
      with_executor { [false, "claude exited 1: 401 API key is invalid"] }
      out, err, status = run(dry_run: false, rounds: 1)

      expect(out).to include("FAIL")
      expect(unwrapped(err)).to include("001.00 luke-backend: claude exited 1: 401 API key is invalid")
      expect(status).to eq(1)
    end

    # The warning has to land before the run, because the failure it predicts
    # arrives three minutes later, once per agent, looking like an agent bug.
    it "warns up front when a credential in the shell will shadow the login" do
      with_executor
      allow(OpenLanes::Execution::Executor).to receive(:foreign_credentials).and_return(["ANTHROPIC_API_KEY"])
      _out, err, = run(dry_run: false, rounds: 1)

      expect(unwrapped(err)).to include("ANTHROPIC_API_KEY is set in this shell", "401 API key is invalid")
    end
  end

  # Plan 009: a plan others wait on, blocked eight days, becomes 💣 on the
  # first sweep, and nothing else starts.
  describe "a 💣" do
    before do
      path = nil
      plans do |t|
        path = t.plan "001.00", :blocked, "feed", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Which feed?\n" }
        t.plan "002.00",
          :building,
          "consumer",
          files: { "spec.md" => "---\ndepends_on: [\"001.00\"]\n---\n#{spec_body}", "plan.md" => "# Plan", "plan-frontend.md" => "## F1" }
      end
      OpenLanes::Plans::PlanState.for(path).sign!(agent: "luke-backend", round: 1, status: "Blocked", at: Time.now - (8 * 86_400))
    end

    it "exits 1 and names the plan on STDERR, even when quiet" do
      executor = with_executor
      _out, err, status = run(dry_run: false, quiet: true)

      aggregate_failures do
        expect(status).to eq(1)
        expect(unwrapped(err)).to include("Halted", "001.00 Feed")
        expect(executor).not_to have_received(:call)
      end
    end

    it "exits 0 under --ignore-bombs, with the 💣 left standing" do
      with_executor
      _out, _err, status = run(dry_run: false, ignore_bombs: true)

      expect(status).to eq(0)
      expect(OpenLanes::Plans::Tree.new(dir: plans_root).find("001.00").status.key).to eq(:bomb)
    end

    it "reads --ignore-bombs off the command line" do
      expect(typed("--ignore-bombs")).to include(ignore_bombs: true)
    end
  end

  describe "the state file" do
    before { building_plan }

    # The run's memory sits in .plans/ beside the plan folders. It is about
    # one machine and must not ride along in a commit, so somebody's
    # .gitignore is edited once, and the edit is announced once.
    it "adds the state file to .gitignore once and says so" do
      root = File.dirname(plans_root)
      system("git", "-C", root, "init", "-q")
      with_executor
      _out, first, = run(dry_run: false)
      _out, second, = run(dry_run: false)

      aggregate_failures do
        expect(unwrapped(first)).to include("Added .plans/openlanes-state.json")
        expect(unwrapped(second)).not_to include("Added .plans/openlanes-state.json")
        expect(File.read(File.join(root, ".gitignore")).scan(%r{^\.plans/openlanes-state\.json$}).size).to eq(1)
      end
    end

    it "touches neither .gitignore nor the state file on a dry run" do
      root = File.dirname(plans_root)
      system("git", "-C", root, "init", "-q")
      run

      aggregate_failures do
        expect(File).not_to exist(File.join(root, ".gitignore"))
        expect(File).not_to exist(File.join(plans_root, OpenLanes::Engine::StateFile::FILENAME))
      end
    end
  end

  describe "worktree isolation with a repository to isolate in" do
    # The real thing shells out to `git worktree add`; the double answers the
    # two questions the command asks — is this a repository, and where does
    # this plan's checkout live — so the wiring to {Publisher} is exercised
    # without git. The checkout is a plain directory, which `dirty?` reads as
    # clean, so the publisher is constructed and then rightly never pushes.
    it "wires a publisher in and runs each plan in its own checkout" do
      building_plan
      checkout = OpenLanes::Vcs::Worktree::Checkout.new(
        ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
        branch:  "kig/001.00-tax-rule-dsl",
        path:    plans_root,
        created: true
      )
      worktree = instance_double(OpenLanes::Vcs::Worktree, repository?: true, checkout_for: checkout, refresh: nil)
      allow(OpenLanes::Vcs::Worktree).to receive(:new).and_return(worktree)
      # Publishing migrates and syncs review labels first; without this the
      # spec would run the real `gh` against whatever repository the suite is
      # checked out in.
      owed = OpenLanes::Vcs::LabelMigration::Outcome.new(pending: false, moves: {})
      allow(OpenLanes::Vcs).to receive_messages(
        label_sync:      instance_double(OpenLanes::Vcs::LabelSync, call: []),
        label_migration: instance_double(OpenLanes::Vcs::LabelMigration, call: owed)
      )

      out, err, status = run(isolation: "worktree")

      expect(out).to include("001.00  luke-backend")
      expect(unwrapped(err)).to include("one worktree each")
      expect(status).to eq(0)
    end
  end

  describe "a tree with nothing an agent may touch" do
    it "declares the fixed point when every plan is settled" do
      plans { |t| t.plan("001.00", :approved, "shipped", prs: [t.merged(2, "Ship it")]) }
      _out, err, status = run(dry_run: false)

      expect(unwrapped(err)).to include("Every plan is done or deliberately parked")
      expect(status).to eq(0)
    end

    # ⭕ is stepped around, never assigned — and stepping around in silence
    # would leave the human unaware they are the bottleneck.
    it "names the plans waiting on a human, with the unblock line to type" do
      plans { |t| t.plan("001.00", :blocked, "stuck", files: { "blocked.md" => "# Blocked\n\n## B1. Which vendor\n" }) }
      _out, err, = run

      expect(unwrapped(err)).to include("1 plan need", "openlanes unblock 001.00")
    end
  end

  # Plan 004: a real run publishes its board to Redis and takes commands from
  # it; a dry run and a run without Redis go on exactly as before, saying so.
  describe "the live board" do
    subject(:stderr) { unwrapped(result[1]) }

    let(:result) { run(dry_run: false, rounds: 1) }

    before do
      building_plan
      with_executor
    end

    it "says where the board is published, and as whom" do
      expect(stderr).to include("Live board: memory:// as")
    end

    it "publishes while the run lasts and takes its snapshot down at the end" do
      result
      aggregate_failures do
        expect(live_store.scan("openlanes:").grep(/:board\z/).map { live_store.xlen(it) }).to all(be_positive)
        expect(live_store.scan("openlanes:").grep(/:snapshot\z/)).to eq([])
      end
    end

    context "without Redis" do
      before { allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 is unavailable") }

      it "runs anyway and says what is missing" do
        expect(stderr).to include("Redis at redis://h/0 is unavailable", "The run goes on without the live board", "2 failed")
      end
    end

    context "with --redis-url" do
      let(:result) { run(dry_run: false, rounds: 1, redis_url: "redis://elsewhere:6380/2") }

      it "connects there" do
        result
        expect(OpenLanes::Live).to have_received(:connect).with("redis://elsewhere:6380/2")
      end
    end

    context "with --dry-run" do
      let(:result) { run }

      it "stays off, and says so" do
        aggregate_failures do
          expect(stderr).to include("Dry run: the live board is off")
          expect(OpenLanes::Live).not_to have_received(:connect)
        end
      end

      it "starts no control room" do
        result
        expect(OpenLanes::Web).not_to have_received(:launcher)
      end
    end
  end

  # Where the run writes, what it publishes to and where its page is: one
  # Info box with a labelled line each, not a box per line, and a line that
  # does not apply left out rather than drawn empty.
  describe "the startup box" do
    subject(:err) { result[1] }

    let(:result) { run(dry_run: false, rounds: 1) }

    before do
      building_plan
      with_executor
    end

    def boxes = err.scan("─ Info ─").size

    it "holds the log, the board and the control room in one box, labels aligned" do
      aggregate_failures do
        expect(boxes).to eq(1)
        expect(err).to match(%r{│  Log: +/\S+}).and include("progress.log")
        expect(err).to match(%r{│  Live board:   memory:// as \S+})
        expect(err).to include('│  Control room: http://127.0.0.1:11000')
      end
    end

    context "with --no-web" do
      let(:result) { run(dry_run: false, rounds: 1, web: false) }

      it "leaves the control room out" do
        expect([boxes, err]).to match([1, satisfy { !it.include?("Control room") && it.include?("Live board:") }])
      end
    end

    context "without Redis" do
      before { allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 is unavailable") }

      it "says only where the log is" do
        expect([boxes, err]).to match([1, satisfy { !it.include?("Live board") && it.include?("Log:") }])
      end
    end

    context "when the engine stays up with its page" do
      before do
        allow(OpenLanes::Engine::Runner).to receive(:new).and_wrap_original do |original, **keywords|
          original.call(**keywords, sleeper: ->(_) { OpenLanes::Execution::Control.quit! })
        end
      end

      after { OpenLanes::Execution::Control.reset! }

      let(:result) { run(dry_run: false, rounds: 1, until_settled: false) }

      it "says so in the same box" do
        expect([boxes, unwrapped(err)]).to match([1, include("Control room:", "The engine stays up with its control room")])
      end
    end

    context "with --quiet" do
      let(:result) { run(dry_run: false, rounds: 1, quiet: true) }

      it "draws none" do
        expect(boxes).to eq(0)
      end
    end
  end

  describe "the control room" do
    subject(:stderr) { unwrapped(result[1]) }

    let(:result) { run(dry_run: false, rounds: 1, port: "4848") }

    before do
      building_plan
      with_executor
    end

    it "starts beside the run on the store the board is published to, and prints its URL" do
      result
      aggregate_failures do
        expect(OpenLanes::Web).to have_received(:launcher).with(root: File.dirname(plans_root), plans_dir: plans_root, port: 4848, redis_url: "memory://")
        expect(stderr).to include("Control room: http://127.0.0.1:11000")
      end
    end

    it "names the port it asked for when the server had to move off it" do
      result
      expect(stderr).to include("Control room: http://127.0.0.1:11000 (4848 was taken)")
    end

    it "opens the browser" do
      result
      expect(OpenLanes::Web).to have_received(:open).with("http://127.0.0.1:11000")
    end

    it "stops it when the run ends" do
      result
      expect(web).to have_received(:stop)
    end

    context "without --until-settled" do
      # Stops the run the way Stop All Local does, once it has idled a while.
      before do
        allow(OpenLanes::Engine::Runner).to receive(:new).and_wrap_original do |original, **keywords|
          ticks = 0
          original.call(**keywords, sleeper: ->(_) { OpenLanes::Execution::Control.quit! if (ticks += 1) > 3 })
        end
      end

      after { OpenLanes::Execution::Control.reset! }

      let(:result) { run(dry_run: false, rounds: 1, until_settled: false) }

      it "keeps the engine up past the fixed point, until it is stopped" do
        result
        aggregate_failures do
          expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_including(stay: true))
          expect(OpenLanes::Engine::Runner).to have_received(:new)
            .with(hash_including(watch: an_instance_of(OpenLanes::Engine::PrWatch)))
          expect(stderr).to include("The engine stays up with its control room: Stop All Local or Ctrl-C ends it.")
          expect(web).to have_received(:stop)
        end
      end
    end

    context "with --no-web --stay, the page served apart" do
      before do
        allow(OpenLanes::Engine::Runner).to receive(:new).and_wrap_original do |original, **keywords|
          ticks = 0
          original.call(**keywords, sleeper: ->(_) { OpenLanes::Execution::Control.quit! if (ticks += 1) > 3 })
        end
      end

      after { OpenLanes::Execution::Control.reset! }

      let(:result) { run(dry_run: false, rounds: 1, until_settled: false, web: false, stay: true) }

      it "starts no server, and stays up for the page all the same" do
        result
        aggregate_failures do
          expect(OpenLanes::Web).not_to have_received(:launcher)
          expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_including(stay: true))
          expect(stderr).to include("The engine stays up for the control room `openlanes web` serves")
        end
      end

      it "warns about nothing it cannot keep" do
        expect(stderr).not_to include("--stay")
      end
    end

    context "with --no-web --stay but no Redis" do
      before { allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 is unavailable") }

      let(:result) { run(dry_run: false, rounds: 1, until_settled: false, web: false, stay: true) }

      it "says the run ends at the fixed point, and ends there" do
        result
        aggregate_failures do
          expect(stderr).to include("--stay needs the live board (Redis) a separate page reads, and this run has none, " \
                                    "so it ends at the first fixed point.")
          expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_excluding(:stay))
        end
      end
    end

    context "with --stay and --until-settled" do
      let(:result) { run(dry_run: false, rounds: 1, web: false, stay: true) }

      it "says --stay is ignored, once, and ends at the fixed point" do
        result
        aggregate_failures do
          expect(stderr.scan("--stay is ignored with --until-settled").size).to eq(1)
          expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_excluding(:stay))
        end
      end
    end

    context "with --no-web alone" do
      let(:result) { run(dry_run: false, rounds: 1, until_settled: false, web: false) }

      it "ends at the fixed point" do
        result
        expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_excluding(:stay, :watch))
      end
    end

    context "with --until-settled" do
      it "ends at the fixed point, as CI wants, watching no pull request" do
        result
        expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_excluding(:stay, :watch))
      end
    end

    context "with --no-open" do
      let(:result) { run(dry_run: false, rounds: 1, open: false) }

      it "only prints the URL" do
        aggregate_failures do
          expect(stderr).to include("Control room: http://127.0.0.1:11000")
          expect(OpenLanes::Web).not_to have_received(:open)
        end
      end
    end

    context "with --no-web" do
      let(:result) { run(dry_run: false, rounds: 1, web: false) }

      it "runs headless, and ends at the fixed point" do
        result
        aggregate_failures do
          expect(OpenLanes::Web).not_to have_received(:launcher)
          expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_excluding(:stay))
        end
      end
    end

    context "without Redis" do
      before { allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 is unavailable") }

      it "runs headless, since there is no board to show" do
        result
        expect(OpenLanes::Web).not_to have_received(:launcher)
      end
    end

    context "when the server does not come up" do
      before { allow(web).to receive(:ready?).and_return(false) }

      it "says so, points at its log, and goes on without it" do
        aggregate_failures do
          expect(stderr).to include("The control room did not answer on http://127.0.0.1:11000", "/tmp/web.log")
          expect(OpenLanes::Web).not_to have_received(:open)
          expect(web).to have_received(:stop)
        end
      end
    end
  end
end
