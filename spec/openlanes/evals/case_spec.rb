# frozen_string_literal: true

require "yaml"

RSpec.describe OpenLanes::Evals::Case, :tree do
  subject(:kase) { described_class.load(path, registry:) }

  let(:registry) { OpenLanes::Agents.registry }
  let(:root) { File.join(File.dirname(plans_root), "cases") }
  let(:folder) { "researcher" }
  let(:data) do
    {
      "id"          => "sample",
      "agent"       => "researcher",
      "depth"       => "fast",
      "description" => "A sample.",
      "fixture"     => { "state" => "new", "files" => { "spec.md" => "# Sample\n" } },
      "expect"      => {
        "state" => "researched",
        "depth" => {
          "fast" => { "max_tokens" => 10, "words" => { "file" => "spec.md", "min" => 1 } },
          "deep" => { "max_tokens" => 99 }
        }
      }
    }
  end
  let(:text) { YAML.dump(data) }
  let(:path) do
    File.join(root, folder, "sample.yml").tap do |p|
      FileUtils.mkdir_p(File.dirname(p))
      File.write(p, text)
    end
  end

  describe "a valid case" do
    it "reads the agent, the depth and the fixture" do
      expect([kase.agent, kase.depth, kase.fixture.state, kase.fixture.slug, kase.fixture.repo])
        .to eq(["researcher", :fast, :new, "sample", {}])
    end

    it "is named agent/id" do
      expect(kase.to_s).to eq("researcher/sample")
    end

    it "keeps its recordings in a directory named after itself" do
      expect(kase.dir).to eq(File.join(root, folder, "sample"))
    end

    it "has no recording until one is written" do
      expect(kase.recording(:pass)).to be_nil
    end

    it "finds a recording once its plan folder exists" do
      FileUtils.mkdir_p(File.join(kase.dir, "fail", "plan"))

      expect(kase.recording(:fail).kind).to eq(:fail)
    end

    it "applies the bounds of its own depth" do
      expect(kase.bounds["max_tokens"]).to eq(10)
    end

    it "applies another depth's bounds when held to it" do
      expect(kase.at(:deep).bounds["max_tokens"]).to eq(99)
    end

    it "has no bounds at a depth it says nothing about" do
      expect(kase.at("medium").bounds).to eq({})
    end

    it "keeps its own depth when none is given" do
      expect(kase.at(nil)).to equal(kase)
    end

    it "refuses to be held to a depth that does not exist" do
      expect { kase.at(:abyssal) }.to raise_error(OpenLanes::Evals::Invalid, /depth :abyssal/)
    end

    it "builds its checks, outcome first" do
      expect(kase.checks.map(&:kind)).to eq(%i[state words tokens])
    end
  end

  describe "the case directory" do
    before { path }

    it "loads every case under it" do
      expect(described_class.all(root, registry:).map(&:id)).to eq(%w[sample])
    end
  end

  # Each of these would otherwise be a check that silently never runs.
  {
    "an agent nobody defined"             => [->(d) { d["agent"] = "nobody" }, /names no agent called "nobody"/],
    "an agent filed under another"        => [->(d) { d["agent"] = "spec-writer" }, %r{sits under researcher/}],
    "an id unlike its file"               => [->(d) { d["id"] = "other" }, /must match the file name/],
    "an unknown depth"                    => [->(d) { d["depth"] = "bottomless" }, /depth "bottomless" is not one of/],
    "an unknown top-level key"            => [->(d) { d["expects"] = {} }, /expects: unknown/],
    "no fixture"                          => [->(d) { d.delete("fixture") }, /has no fixture/],
    "an unknown fixture key"              => [->(d) { d["fixture"]["branch"] = "x" }, /fixture.branch: unknown/],
    "a fixture state that is no status"   => [->(d) { d["fixture"]["state"] = "pending" }, /fixture.state "pending"/],
    "fixture files that are a list"       => [->(d) { d["fixture"]["files"] = ["spec.md"] }, /fixture.files must map/],
    "a fixture without spec.md"           => [->(d) { d["fixture"]["files"] = { "plan.md" => "" } }, /no spec.md/],
    "no expectations"                     => [->(d) { d.delete("expect") }, /has no expect/],
    "a misspelt expectation"              => [->(d) { d["expect"]["stat"] = "x" }, /expect.stat: unknown/],
    "an expected state that is no status" => [->(d) { d["expect"]["state"] = "done" }, /expect.state "done"/],
    "depth bounds that are a list"        => [->(d) { d["expect"]["depth"] = [] }, /expect.depth must map/],
    "bounds for an unknown depth"         => [->(d) { d["expect"]["depth"]["huge"] = {} }, /depth "huge"/],
    "bounds that are not a mapping"       => [->(d) { d["expect"]["depth"]["fast"] = 3 }, /expect.depth.fast must be a mapping/],
    "an unknown bound"                    => [->(d) { d["expect"]["depth"]["fast"]["pages"] = 3 }, /expect.depth.fast.pages: unknown/],
    "a bound entry that is no mapping"    => [->(d) { d["expect"]["depth"]["fast"]["words"] = ["x"] }, /words must be a mapping/],
    "an unknown key in a bound"           => [->(d) { d["expect"]["depth"]["fast"]["words"]["lines"] = 3 }, /words.lines: unknown/]
  }.each do |label, (mutate, message)|
    context "with #{label}" do
      let(:data) { super().tap(&mutate) }

      it "refuses it" do
        expect { kase }.to raise_error(OpenLanes::Evals::Invalid, message)
      end
    end
  end

  context "with a file that is not YAML" do
    let(:text) { "id: [unclosed\n" }

    it "refuses it, naming the file" do
      expect { kase }.to raise_error(OpenLanes::Evals::Invalid, /sample.yml: is not valid YAML/)
    end
  end

  context "with YAML that is not a mapping" do
    let(:text) { "- one\n- two\n" }

    it "refuses it" do
      expect { kase }.to raise_error(OpenLanes::Evals::Invalid, /is not a mapping/)
    end
  end
end
