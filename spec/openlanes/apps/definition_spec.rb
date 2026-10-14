# frozen_string_literal: true

# The `app:` block, parsed on its own. {OpenLanes::Config} hands it here,
# and config_spec checks the file is named through that path too.
RSpec.describe OpenLanes::Apps::Definition do
  let(:path) { "/work/.openlanes.yml" }

  def parse(value) = described_class.parse(value, path:)

  def two(**web) = { "kind" => "web", "processes" => [{ "name" => "api", "start" => "bin/api" }, { "name" => "web", "start" => "bin/web", **web }] }

  describe ".parse" do
    it "keeps the processes in declared order, with their settings" do
      definition = parse(two("ready" => "/", "restart_on" => "src/**/*", "preview" => true))
      expect(definition.processes.map(&:to_h)).to eq(
        [{ "name" => "api", "start" => "bin/api" },
         { "name" => "web", "start" => "bin/web", "ready" => "/", "restart_on" => ["src/**/*"], "preview" => true }]
      )
    end

    it "records the kind as written" do
      expect(parse(two).kind).to eq("web")
    end

    it "round-trips through to_h" do
      definition = parse(two("preview" => true, "restart_on" => ["a", "b"]))
      expect(parse(definition.to_h)).to eq(definition)
    end

    {
      "something that is not a mapping"   => ["web", /app: must be a mapping/],
      "an unknown key in app"             => [{ "processes" => [{ "name" => "a", "start" => "x" }], "proc" => 1 }, /app: unknown key proc; known: kind, processes/],
      "no processes"                      => [{ "processes" => [] }, /app.processes: must be a list of at least one/],
      "a process that is not a mapping"   => [{ "processes" => ["web"] }, /app.processes\[0\]: must be a mapping/],
      "an unknown key in a process"       => [{ "processes" => [{ "name" => "a", "start" => "x", "restart-on" => "y" }] }, /app.processes\[0\]: unknown key restart-on/],
      "a process without a name"          => [{ "processes" => [{ "start" => "x" }] }, /app.processes\[0\]: needs name:/],
      "a name a shell would trip over"    => [{ "processes" => [{ "name" => "my app", "start" => "x" }] }, /needs name:/],
      "a process without start"           => [{ "processes" => [{ "name" => "web" }] }, /app.processes.web: needs start:/],
      "a ready that is not a path"        => [{ "processes" => [{ "name" => "web", "start" => "x", "ready" => "up" }] }, /web.ready: "up" is not an HTTP path/],
      "restart_on that is not globs"      => [{ "processes" => [{ "name" => "web", "start" => "x", "restart_on" => [1] }] }, /web.restart_on: must be a glob/],
      "preview that is not boolean"       => [{ "processes" => [{ "name" => "web", "start" => "x", "preview" => "yes" }] }, /web.preview: "yes" is not true or false/],
      "a kind that is not a word"         => [{ "kind" => 3, "processes" => [{ "name" => "a", "start" => "x" }] }, /app.kind: 3 is not a word/],
      "one name twice"                    => [{ "processes" => [{ "name" => "a", "start" => "x" }, { "name" => "a", "start" => "y" }] }, /a named twice/],
      "two names with one PORT_ variable" => [{ "processes" => [{ "name" => "api-v2", "start" => "x" }, { "name" => "api_v2", "start" => "y" }] }, /api-v2 and api_v2 would both be PORT_API_V2/]
    }.each do |what, (value, message)|
      it "refuses #{what}, naming the file" do
        expect { parse(value) }.to raise_error(OpenLanes::Error, /\A#{Regexp.escape(path)}: .*#{message}/)
      end
    end
  end

  describe "#preview" do
    it "is the one process marked preview: true" do
      expect(parse(two("preview" => true)).preview.name).to eq("web")
    end

    it "is nil when no process is marked, which is no tab and no error" do
      expect(parse(two).preview).to be_nil
    end

    it "refuses two" do
      value = { "processes" => [{ "name" => "a", "start" => "x", "preview" => true }, { "name" => "b", "start" => "y", "preview" => true }] }
      expect { parse(value) }.to raise_error(OpenLanes::Error, /only one process may be preview: true, not a and b/)
    end
  end

  describe "#backend" do
    it "is every process but the previewed one, in declared order" do
      value = { "processes" => [{ "name" => "db", "start" => "x" }, { "name" => "web", "start" => "y", "preview" => true }, { "name" => "api", "start" => "z" }] }
      expect(parse(value).backend.map(&:name)).to eq(%w[db api])
    end
  end

  describe "#process" do
    it "finds one by name, and nothing for a name it does not have" do
      definition = parse(two)
      expect([definition.process("api").start, definition.process("nope")]).to eq(["bin/api", nil])
    end
  end
end
