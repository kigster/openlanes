# frozen_string_literal: true

# `.openlanes/config.yml` `agents:`: one machine's changes to an agent, laid
# over its definition and over nothing else.
RSpec.describe OpenLanes::Config, "#agents" do
  def parse(yaml) = described_class.parse(yaml, path: ".openlanes/config.yml")

  def registry(yaml) = OpenLanes::Agents::Registry.new(overrides: parse(yaml).agents)

  let(:definition) { OpenLanes::Agents::Registry.new(overrides: OpenLanes::Agents::Overrides.new).find("backend-coder") }
  let(:tuned) { "agents:\n  backend-coder: { rounds: 3, timeout: 3600, extension_cap: 1200, extension_ceiling: 5400 }\n" }

  describe "parsing" do
    it "is empty when the file says nothing, and writes nothing back" do
      config = parse("jobs: 2\n")
      expect([config.agents.table, config.to_settings.key?("agents")]).to eq([{}, false])
    end

    it "keeps what each agent sets, and writes the same back" do
      config = parse(tuned)
      aggregate_failures do
        expect(config.agents.for("backend-coder")).to eq(rounds: 3, timeout: 3600, extension_cap: 1200, extension_ceiling: 5400)
        expect(parse(config.to_yaml).agents).to eq(config.agents)
      end
    end

    it "reads an entry with nothing set as no entry" do
      expect(parse("agents:\n  planner: { rounds: }\n").agents.table).to eq({})
    end

    it "takes exactly the keys the schema describes" do
      keys = OpenLanes::Config::Schema.static.dig("properties", "agents", "additionalProperties", "properties")
      aggregate_failures do
        expect(OpenLanes::Agents::Overrides::KEYS).to eq(keys.keys)
        expect(keys.dig("effort", "enum").compact).to eq(OpenLanes::Adapters::EFFORTS)
        expect(keys.dig("rounds", "maximum")).to eq(OpenLanes::Agents::Agent::MAX_ROUNDS)
        expect(keys.keys.map(&:to_sym) - OpenLanes::Agents::Agent.members).to eq([])
      end
    end

    {
      "agents: [backend-coder]\n"                         => /agents: must be a mapping of agent name to its settings/,
      "agents:\n  bob: { rounds: 2 }\n"                   => /agents: unknown agent bob; known: .*backend-coder/,
      "agents:\n  planner: 3\n"                           => /agents\.planner: must be a mapping of setting to value/,
      "agents:\n  planner: { speed: 2 }\n"                => /agents\.planner: unknown key speed; known: timeout, rounds/,
      "agents:\n  planner: { rounds: 0 }\n"               => /agents\.planner\.rounds: 0 is not a whole number from 1 to 5/,
      "agents:\n  planner: { rounds: 6 }\n"               => /agents\.planner\.rounds: 6 is not a whole number from 1 to 5/,
      "agents:\n  planner: { rounds: two }\n"             => /agents\.planner\.rounds: "two" is not a whole number/,
      "agents:\n  planner: { timeout: -1 }\n"             => /agents\.planner\.timeout: -1 is not a whole number of seconds above zero/,
      "agents:\n  planner: { timeout: 1.5 }\n"            => /agents\.planner\.timeout: 1\.5 is not a whole number of seconds/,
      "agents:\n  planner: { extension_cap: 0 }\n"        => /agents\.planner\.extension_cap: 0 is not a whole number of seconds/,
      "agents:\n  planner: { extension_ceiling: soon }\n" => /agents\.planner\.extension_ceiling: "soon" is not a whole number/,
      "agents:\n  planner: { effort: lazy }\n"            => /agents\.planner\.effort: "lazy" is not one of low, medium/,
      "agents:\n  planner: { model: 3 }\n"                => /agents\.planner\.model: 3 is not a model name/
    }.each do |yaml, message|
      it "refuses #{yaml.lines.last.strip}" do
        expect { parse(yaml) }.to raise_error(OpenLanes::Error, message)
      end
    end
  end

  describe "in the registry" do
    it "leaves an agent the file does not name exactly as its definition has it" do
      expect(registry(tuned).find("planner")).to eq(OpenLanes::Agents::Registry.new(overrides: OpenLanes::Agents::Overrides.new).find("planner"))
    end

    it "replaces the keys it names and no others" do
      agent = registry(tuned).find("backend-coder")
      aggregate_failures do
        expect(agent.to_h.slice(:rounds, :timeout, :extension_cap, :extension_ceiling))
          .to eq(rounds: 3, timeout: 3600, extension_cap: 1200, extension_ceiling: 5400)
        expect(agent.to_h.except(:rounds, :timeout, :extension_cap, :extension_ceiling))
          .to eq(definition.to_h.except(:rounds, :timeout, :extension_cap, :extension_ceiling))
      end
    end

    it "carries the overrides into a narrowed roster" do
      narrowed = registry(tuned).only("backend-coder").without("planner")
      expect([narrowed.find("backend-coder").rounds, narrowed.overrides.table.keys]).to eq([3, ["backend-coder"]])
    end

    it "reads the project's file when it is handed none" do
      allow(described_class).to receive(:current).and_return(parse(tuned))
      expect(OpenLanes::Agents::Registry.new.find("backend-coder").rounds).to eq(3)
    end

    it "takes the extension settings from a definition that names them" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "planner.md"), "---\nname: planner\nextension_cap: 300\nextension_ceiling: 1200\n---\nPlan.\n")
        agent = OpenLanes::Agents::Registry.new(dir:, overrides: OpenLanes::Agents::Overrides.new).find("planner")
        expect([agent.extension_cap, agent.extension_ceiling]).to eq([300, 1200])
      end
    end

    it "defaults them to fifteen minutes and an hour" do
      expect([definition.extension_cap, definition.extension_ceiling]).to eq([900, 3600])
    end
  end

  describe "what a run reads" do
    let(:agent) { registry(tuned).find("backend-coder") }
    let(:runner) { instance_double(OpenLanes::Engine::Runner, dry_run?: false, executor: nil) }
    let(:profiles) { OpenLanes::Engine::Dispatcher::Desk::Profiles.new(runner:, rounds_cap: nil, extensions: nil) }

    it "counts rounds against the machine's number" do
      expect([profiles.rounds_for(definition), profiles.rounds_for(agent)]).to eq([1, 3])
    end

    it "still lets `--rounds` tighten it" do
      capped = OpenLanes::Engine::Dispatcher::Desk::Profiles.new(runner:, rounds_cap: 2, extensions: nil)
      expect(capped.rounds_for(agent)).to eq(2)
    end

    it "runs the clock on the machine's timeout, which `--timeout` still only tightens" do
      aggregate_failures do
        expect(OpenLanes::Execution::Executor.new(root: Dir.pwd).timeout_for(agent)).to eq(3600)
        expect(OpenLanes::Execution::Executor.new(root: Dir.pwd, timeout: 600).timeout_for(agent)).to eq(600)
      end
    end
  end

  describe "model and effort, in Profile's order" do
    let(:agent) { registry("agents:\n  backend-coder: { model: sonnet, effort: low }\n").find("backend-coder") }

    def spec(frontmatter) = OpenLanes::Plans::Spec.parse("---\n#{frontmatter}\n---\n")

    it "stands where the frontmatter stood" do
      expect(OpenLanes::Agents::Profile.resolve(agent).to_s).to eq("claude:#{OpenLanes::Adapters.for("claude").model("sonnet")}/low")
    end

    it "yields to the plan's own spec.md, which is more specific than the machine's file" do
      profile = OpenLanes::Agents::Profile.resolve(agent, spec: spec("starts: planning\nphases:\n  build: { model: opus, effort: high }"))
      expect(profile.to_s).to eq("claude:#{OpenLanes::Adapters.for("claude").model("opus")}/high")
    end

    it "yields to `run --model`" do
      expect(OpenLanes::Agents::Profile.resolve(agent, model: "fable").model).to eq(OpenLanes::Adapters.for("claude").model("fable"))
    end
  end
end
