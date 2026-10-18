# frozen_string_literal: true

RSpec.describe OpenLanes::Config do
  let(:root) { File.realpath(Dir.mktmpdir("openlanes-config")) }
  let(:path) { File.join(root, ".openlanes.yml") }

  after { FileUtils.rm_rf(root) }

  def openlanes_yml(text) = File.write(path, text)

  describe ".load" do
    subject(:config) { described_class.load(root) }

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
          lane: plan
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
        expect(config).to have_attributes(path:, project: "Equilibris App", lane: :plan, frontend: false, jobs: 4)
      end

      it "folds jobs into run's defaults" do
        expect(config.for(:run)).to eq(timeout: 1800, jobs: 4)
      end

      it "folds lane into create's defaults, as the string a flag would be" do
        expect(config.for(:create)).to eq(lane: "plan")
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

    describe "review.max_hmm" do
      it "defaults to five when neither the file nor the environment says" do
        expect(config.max_hmm(env: {})).to eq(5)
      end

      it "reads the file" do
        openlanes_yml("review:\n  max_hmm: 2\n")
        expect([config.review_max_hmm, config.max_hmm(env: {})]).to eq([2, 2])
      end

      it "lets $OPENLANES_REVIEW_MAX_HMM beat the file" do
        openlanes_yml("review:\n  max_hmm: 2\n")
        expect(config.max_hmm(env: { "OPENLANES_REVIEW_MAX_HMM" => "9" })).to eq(9)
      end

      it "ignores an empty variable" do
        expect(config.max_hmm(env: { "OPENLANES_REVIEW_MAX_HMM" => " " })).to eq(5)
      end

      it "refuses a variable that is not a whole number" do
        expect { config.max_hmm(env: { "OPENLANES_REVIEW_MAX_HMM" => "five" }) }
          .to raise_error(OpenLanes::Error, /OPENLANES_REVIEW_MAX_HMM="five" is not a whole number/)
      end

      {
        "an unknown key"   => ["review:\n  max_rejections: 2\n", /review\.max_rejections: unknown key; known: max_hmm/],
        "a negative count" => ["review:\n  max_hmm: -1\n", /review\.max_hmm: -1 is not a whole number/],
        "a word"           => ["review:\n  max_hmm: five\n", /review\.max_hmm: "five" is not a whole number/],
        "not a mapping"    => ["review: 5\n", /review: must be a mapping/]
      }.each do |label, (text, message)|
        it "refuses #{label}" do
          openlanes_yml(text)
          expect { config }.to raise_error(OpenLanes::Error, message)
        end
      end

      it "writes itself back out under review:" do
        expect(described_class.new(review_max_hmm: 3).to_yaml).to eq("review:\n  max_hmm: 3\n")
      end
    end

    # A config silently ignored is a timeout that stops applying with no
    # signal, so every one of these names the file.
    {
      "an unknown key"                 => ["jobz: 4\n", /unknown key jobz/],
      "a lane that is not one"         => ["lane: fast\n", /lane: "fast" is not one of full, plan, quick/],
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
      openlanes_yml("lane: quick\n")
      expect(OpenLanes::CLI::Create.default_params[:lane]).to eq("quick")
    end

    it "gives index its heading" do
      openlanes_yml("project: Equilibris App\n")
      expect(OpenLanes::CLI::Index.default_params[:project]).to eq("Equilibris App")
    end

    it "loses to a flag typed on the command line" do
      openlanes_yml("lane: quick\n")
      parsed = Dry::CLI::Parser.call(OpenLanes::CLI::Create, %w[--lane plan some words], "openlanes create")
      expect(parsed.arguments[:lane]).to eq("plan")
    end

    it "adds nothing from a file that cannot be read" do
      openlanes_yml("lane: [\n")
      expect(OpenLanes::CLI::Create.default_params).not_to have_key(:lane)
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
end
