# frozen_string_literal: true

RSpec.describe OpenLanes::Config do
  let(:root) { File.realpath(Dir.mktmpdir("openlanes-config")) }
  let(:path) { File.join(root, ".openlanes.yml") }

  after { FileUtils.rm_rf(root) }

  def openlanes_yml(text) = File.write(path, text)

  describe ".load" do
    subject(:config) { described_class.load(root) }

    # Plan 040, D1.
    describe "adapter:" do
      it "names the coding agent every agent without its own runs on" do
        openlanes_yml("adapter: codex\n")
        expect(config.adapter).to eq("codex")
      end

      it "refuses one nothing answers to" do
        openlanes_yml("adapter: cursor\n")
        expect { config }.to raise_error(OpenLanes::Error, /adapter: "cursor" is not one of claude, codex, pi/)
      end

      it "is written back by to_yaml" do
        openlanes_yml("adapter: pi\n")
        expect(config.to_yaml).to eq("adapter: pi\n")
      end
    end

    it "is empty when the root holds no file" do
      expect([config.file?, config.for(:run)]).to eq([false, {}])
    end

    it "is empty for an empty file" do
      openlanes_yml("")
      expect(config.for(:run)).to eq({})
    end

    context "with every key set" do
      before do
        openlanes_yml(<<~YAML)
          project: Equilibris App
          starts: planning
          frontend: false
          jobs: 4
          commands:
            run:
              timeout: 1800
            resync dirs:
              quiet: true
        YAML
      end

      it "reads the top-level settings" do
        expect(config).to have_attributes(path:, project: "Equilibris App", starts: :planning, frontend: false, jobs: 4)
      end

      it "folds jobs into run's defaults" do
        expect(config.for(:run)).to eq(timeout: 1800, jobs: 4)
      end

      it "folds lane into create's defaults, as the string a flag would be" do
        expect(config.for(:create)).to eq(starts: "planning")
      end

      it "folds project into index's defaults" do
        expect(config.for(:index)).to eq(project: "Equilibris App")
      end

      it "keeps a two-word command's section under its typed name" do
        expect(config.for("resync dirs")).to eq(quiet: true)
      end
    end

    describe "plans.aging_since" do
      it "reads an unquoted date" do
        openlanes_yml("plans:\n  aging_since: 2026-10-01\n")
        expect(config.aging_since).to eq(Date.new(2026, 10, 1))
      end

      it "reads a quoted date" do
        openlanes_yml("plans:\n  aging_since: '2026-10-01'\n")
        expect(config.aging_since).to eq(Date.new(2026, 10, 1))
      end

      it "is nil when absent, which is no floor at all" do
        openlanes_yml("jobs: 2\n")
        expect(config.aging_since).to be_nil
      end

      it "writes itself back out under plans:" do
        expect(described_class.new(aging_since: Date.new(2026, 10, 1)).to_yaml).to eq("plans:\n  aging_since: '2026-10-01'\n")
      end
    end

    describe "events:" do
      it "reads enabled and an absolute dir" do
        openlanes_yml("events:\n  enabled: true\n  dir: /var/log/openlanes\n")
        expect(config).to have_attributes(events_enabled: true, events_dir: "/var/log/openlanes")
        expect(config.to_yaml).to include("events:\n  enabled: true\n  dir: \"/var/log/openlanes\"")
      end

      it "is off with no directory when absent" do
        openlanes_yml("jobs: 2\n")
        expect(config).to have_attributes(events_enabled: false, events_dir: nil)
        expect(config.to_yaml).not_to include("events")
      end

      it "refuses a value that is not a mapping" do
        openlanes_yml("events: true\n")
        expect { config }.to raise_error(OpenLanes::Error, /events: must be a mapping/)
      end

      it "refuses a key it does not know" do
        openlanes_yml("events:\n  sink: postgres\n")
        expect { config }.to raise_error(OpenLanes::Error, /events\.sink: unknown key; known: enabled, dir/)
      end

      it "refuses an enabled that is not a boolean" do
        openlanes_yml("events:\n  enabled: sometimes\n")
        expect { config }.to raise_error(OpenLanes::Error, /events\.enabled: "sometimes" is not true or false/)
      end

      it "refuses a relative dir" do
        openlanes_yml("events:\n  dir: log/events\n")
        expect { config }.to raise_error(OpenLanes::Error, %r{events\.dir: "log/events" is not an absolute path})
      end
    end

    describe "questions.model" do
      it "reads the model that rewrites prose questions" do
        openlanes_yml("questions:\n  model: google/gemini-3.5-flash\n")
        expect(config.questions_model).to eq("google/gemini-3.5-flash")
      end

      it "is nil when absent, which takes the converter's default" do
        openlanes_yml("jobs: 2\n")
        expect(config.questions_model).to be_nil
      end

      it "refuses a key it does not know" do
        openlanes_yml("questions:\n  effort: low\n")
        expect { config }.to raise_error(OpenLanes::Error, /questions\.effort: unknown key; known: model/)
      end

      it "refuses a model that is not a name" do
        openlanes_yml("questions:\n  model: 42\n")
        expect { config }.to raise_error(OpenLanes::Error, /questions\.model: 42 is not a model id/)
      end

      it "refuses questions: that is not a mapping" do
        openlanes_yml("questions: haiku\n")
        expect { config }.to raise_error(OpenLanes::Error, /questions: must be a mapping/)
      end

      it "writes itself back out under questions:" do
        expect(described_class.new(questions_model: "m/x").to_yaml).to eq("questions:\n  model: m/x\n")
      end
    end

    # Plan 031, D11.
    describe "review.adapters" do
      it "lists the coding agents the reviewers are dealt across, main one first" do
        openlanes_yml("review:\n  adapters: [codex, claude]\n")
        expect(config.review_adapters).to eq(%w[codex claude])
      end

      it "is empty when unset, so every reviewer runs on adapter:" do
        openlanes_yml("jobs: 2\n")
        expect(config.review_adapters).to eq([])
      end

      it "refuses a coding agent nothing answers to" do
        openlanes_yml("review:\n  adapters: [claude, cursor]\n")
        expect { config }.to raise_error(OpenLanes::Error, /review\.adapters: cursor is not one of claude/)
      end

      it "refuses one named twice" do
        openlanes_yml("review:\n  adapters: [codex, claude, codex]\n")
        expect { config }.to raise_error(OpenLanes::Error, /review\.adapters: codex is named twice/)
      end

      it "refuses a key it does not know" do
        openlanes_yml("review:\n  models: [opus]\n")
        expect { config }.to raise_error(OpenLanes::Error, /review: unknown key models; known: adapters/)
      end

      it "refuses review: that is not a mapping" do
        openlanes_yml("review: codex\n")
        expect { config }.to raise_error(OpenLanes::Error, /review: must be a mapping/)
      end

      it "writes itself back out under review:" do
        expect(described_class.new(review_adapters: %w[claude codex]).to_yaml).to eq("review:\n  adapters:\n  - claude\n  - codex\n")
      end
    end

    # W32
    describe "redis_outage_hours" do
      it "gives up on a lost Redis after an hour when the file says nothing" do
        expect([config.redis_outage_hours, config.outage_limit]).to eq([nil, 3600.0])
      end

      it "reads any positive number of hours" do
        openlanes_yml("redis_outage_hours: 0.5\n")
        expect(config.outage_limit).to eq(1800.0)
      end

      it "writes itself back out" do
        expect(described_class.new(redis_outage_hours: 6).to_yaml).to eq("redis_outage_hours: 6\n")
      end

      { "zero" => "0", "a negative" => "-2", "a word" => "soon" }.each do |label, value|
        it "refuses #{label}" do
          openlanes_yml("redis_outage_hours: #{value}\n")
          expect { config }.to raise_error(OpenLanes::Error, /redis_outage_hours: .* is not a number of hours above zero/)
        end
      end
    end

    describe "redis_backoff" do
      it "is empty when the file says nothing, so Live::Outage applies its defaults" do
        expect(config.redis_backoff).to eq({})
      end

      it "reads initial, cap and jitter" do
        openlanes_yml("redis_backoff:\n  initial: 2\n  cap: 10\n  jitter: false\n")
        expect(config.redis_backoff).to eq(initial: 2, cap: 10, jitter: false)
      end

      it "writes itself back out" do
        expect(described_class.new(redis_backoff: { cap: 10 }).to_yaml).to eq("redis_backoff:\n  cap: 10\n")
      end

      {
        "a list"            => ["redis_backoff: [1]\n", /redis_backoff: must be a mapping/],
        "an unknown key"    => ["redis_backoff:\n  max: 3\n", /redis_backoff.max: unknown key; known: initial, cap, jitter/],
        "a zero cap"        => ["redis_backoff:\n  cap: 0\n", /redis_backoff.cap: 0 is not a number of seconds above zero/],
        "a word for jitter" => ["redis_backoff:\n  jitter: full\n", /redis_backoff.jitter: "full" is not true or false/]
      }.each do |label, (yaml, message)|
        it "refuses #{label}" do
          openlanes_yml(yaml)
          expect { config }.to raise_error(OpenLanes::Error, message)
        end
      end
    end

    # V4 dropped R3's pooled emoji count, and its threshold with it.
    it "refuses review.max_hmm as an unknown key" do
      openlanes_yml("review:\n  max_hmm: 5\n")
      expect { config }.to raise_error(OpenLanes::Error, /review: unknown key max_hmm; known: adapters/)
    end

    # A config silently ignored is a timeout that stops applying with no
    # signal, so every one of these names the file.
    {
      "an unknown key"                 => ["jobz: 4\n", /unknown key jobz/],
      "a lane that is not one"         => ["starts: fast\n", /starts: "fast" is not one of research, planning, building/],
      "a frontend that is not boolean" => ["frontend: maybe\n", /frontend: "maybe" is not true or false/],
      "jobs that are not a count"      => ["jobs: 0\n", /jobs: 0 is not a whole number/],
      "a blank project"                => ["project: ' '\n", /project: must be a non-empty name/],
      "a list at the top"              => ["- jobs\n", /expected a mapping/],
      "commands that are not a map"    => ["commands: run\n", /commands: must be a mapping/],
      "a command that is not a map"    => ["commands:\n  run: 3\n", /commands.run: must be a mapping/],
      "broken YAML"                    => ["commands: [\n", /not valid YAML/],
      "plans that are not a map"       => ["plans: soon\n", /plans: must be a mapping/],
      "a malformed aging date"         => ["plans:\n  aging_since: last week\n", /plans.aging_since: "last week" is not a date/],
      "an impossible aging date"       => ["plans:\n  aging_since: '2026-02-30'\n", /plans.aging_since: .* is not a date/],
      "an unknown key under plans"     => ["plans:\n  aging: 2026-10-01\n", /plans.aging: unknown key/],
      "jobs said twice"                => ["jobs: 2\ncommands:\n  run:\n    jobs: 3\n", /jobs and commands.run.jobs are the same setting/],
      "an unknown key inside app"      => ["app:\n  processes:\n    - {name: web, start: x, port: 1}\n", /app.processes\[0\]: unknown key port/],
      "an app process without start"   => ["app:\n  processes:\n    - name: web\n", /app.processes.web: needs start:/],
      "an app process without a name"  => ["app:\n  processes:\n    - start: bin/web\n", /app.processes\[0\]: needs name:/]
    }.each do |what, (text, message)|
      it "refuses #{what}, naming the file" do
        openlanes_yml(text)
        expect { config }.to raise_error(OpenLanes::Error, /\A#{Regexp.escape(path)}: .*#{message}/m)
      end
    end
  end

  describe "app:" do
    subject(:config) { described_class.load(root) }

    before do
      openlanes_yml(<<~YAML)
        app:
          kind: web
          processes:
            - name: api
              start: bin/rails s -p $PORT_API
              ready: /up
              restart_on: ["app/**/*.rb", "config/**/*"]
            - name: web
              start: npx vite --port $PORT_WEB --strictPort
              ready: /
              preview: true
      YAML
    end

    it "loads the processes in declared order" do
      expect(config.app.processes.map(&:name)).to eq(%w[api web])
    end

    it "is what Apps.definition answers" do
      expect(OpenLanes::Apps.definition(config).preview.name).to eq("web")
    end

    it "is written back by to_yaml, so init keeps it" do
      expect(described_class.parse(config.to_yaml, path:).app).to eq(config.app)
    end

    it "is nil in a project that declares none" do
      openlanes_yml("jobs: 2\n")
      expect(described_class.load(root).app).to be_nil
    end
  end

  describe "ci: and stack:" do
    subject(:config) { described_class.load(root) }

    let(:full) do
      <<~YAML
        ci:
          provider: github_actions
          config: .github/workflows/ci.yml
        stack:
          language: ruby
          frameworks: [rails, sinatra]
          persistence: postgres
          from: sinatra
          to: rails
      YAML
    end

    it "reads each of them" do
      openlanes_yml(full)
      expect(config).to have_attributes(
        ci:    { provider: :github_actions, config: ".github/workflows/ci.yml" },
        stack: { language: "ruby", frameworks: %w[rails sinatra], persistence: "postgres",
                         from: "sinatra", to: "rails" }
      )
    end

    it "round-trips them through to_yaml" do
      openlanes_yml(full)
      expect(described_class.parse(config.to_yaml, path:)).to have_attributes(
        ci: config.ci, stack: config.stack
      )
    end

    it "takes a CI provider without a config file" do
      openlanes_yml("ci: { provider: none }\n")
      expect(config.ci).to eq(provider: :none, config: nil)
    end

    it "loads an older file that has none of them" do
      openlanes_yml("starts: planning\n")
      expect(config).to have_attributes(ci: nil, stack: nil)
    end

    it "leaves them out of the file when unset" do
      expect(described_class.new(starts: :planning).to_yaml).to eq("starts: planning\n")
    end

    {
      "ci: { provider: travis }"           => /ci.provider: "travis" is not one of/,
      "ci: { provider: none, runner: x }"  => /ci: unknown key runner/,
      "ci: github_actions"                 => /ci: must be a mapping/,
      "ci: { provider: none, config: 3 }"  => /ci.config: must be a path/,
      "stack: ruby"                        => /stack: must be a mapping/,
      "stack: { language: ruby, os: mac }" => /stack: unknown field os/,
      "stack: { language: '  ' }"          => /stack.language: must be a non-empty name/,
      "stack: { frameworks: [rails, 3] }"  => /stack.frameworks: must be a list of names/
    }.each do |text, message|
      it "refuses #{text}" do
        openlanes_yml("#{text}\n")
        expect { config }.to raise_error(OpenLanes::Error, message)
      end
    end
  end

  describe ".current" do
    before { Dir.chdir(root) }

    it "reads the file at the working project's root" do
      FileUtils.mkdir_p(File.join(root, ".plans"))
      openlanes_yml("jobs: 2\n")
      expect(described_class.current.jobs).to eq(2)
    end

    it "rereads the file once it changes" do
      openlanes_yml("jobs: 2\n")
      described_class.current
      openlanes_yml("jobs: 5\n")
      File.utime(Time.now + 5, Time.now + 5, path)
      expect(described_class.current.jobs).to eq(5)
    end
  end

  # Typed flags beat these; that is dry-cli's merge, so the CLI only has to
  # put the file between the flag and the built-in default.
  describe "as command defaults" do
    before do
      FileUtils.mkdir_p(File.join(root, ".plans"))
      Dir.chdir(root)
    end

    it "gives create its lane" do
      openlanes_yml("starts: building\n")
      expect(OpenLanes::CLI::Create.default_params[:starts]).to eq("building")
    end

    it "gives index its heading" do
      openlanes_yml("project: Equilibris App\n")
      expect(OpenLanes::CLI::Index.default_params[:project]).to eq("Equilibris App")
    end

    it "loses to a flag typed on the command line" do
      openlanes_yml("starts: building\n")
      parsed = Dry::CLI::Parser.call(OpenLanes::CLI::Create, %w[--starts planning some words], "openlanes create")
      expect(parsed.arguments[:starts]).to eq("planning")
    end

    it "adds nothing from a file that cannot be read" do
      openlanes_yml("starts: [\n")
      expect(OpenLanes::CLI::Create.default_params).not_to have_key(:starts)
    end
  end

  describe "OpenLanes::CLI::Base.check_config!" do
    def check(text)
      openlanes_yml(text)
      OpenLanes::CLI::Base.check_config!(described_class.load(root))
    end

    it "accepts options the command takes" do
      expect { check("commands:\n  run:\n    isolation: shared\n    user_config: true\n") }.not_to raise_error
    end

    {
      "a command that does not exist" => ["commands:\n  sprint: {}\n", /commands.sprint: no such command/],
      "an alias for a command"        => ["commands:\n  st: {}\n", /commands.st: no such command/],
      "an option it does not take"    => ["commands:\n  run:\n    speed: 3\n", /run takes no such option/],
      "a value outside its list"      => ["commands:\n  run:\n    isolation: cloud\n", /"cloud" is not one of worktree, shared/],
      "a boolean that is not one"     => ["commands:\n  run:\n    user_config: yes please\n", /is not true or false/],
      "dry_run as a default"          => ["commands:\n  run:\n    dry_run: true\n", /never set as a default/]
    }.each do |what, (text, message)|
      it "refuses #{what}" do
        expect { check(text) }.to raise_error(OpenLanes::Error, message)
      end
    end
  end

  describe "architecture_decisions:" do
    let(:path) { "/tmp/.openlanes.yml" }
    let(:yaml) { "architecture_decisions:\n  version: 1\n  current:\n    ci:\n    - circleci\n  target:\n    ci:\n    - github_actions\n" }

    it "round-trips through the file" do
      config = described_class.parse(yaml, path:)
      expect([config.architecture_decisions.target.ci, config.to_yaml]).to match([%i[github_actions], include("architecture_decisions:", "- circleci")])
    end

    it "refuses what the closed lists do not hold" do
      expect { described_class.parse("architecture_decisions:\n  target:\n    ci:\n    - travis\n", path:) }
        .to raise_error(OpenLanes::Error, /architecture_decisions/)
    end
  end
end
