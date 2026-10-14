# frozen_string_literal: true

RSpec.describe OpenLanes::Apps::Watcher do
  let(:root) { File.realpath(Dir.mktmpdir("openlanes-watcher")) }
  let(:definition) do
    OpenLanes::Apps::Definition.new(kind: "web",
      processes: [
        OpenLanes::Apps::ProcessSpec.new(name: "api", start: "x", restart_on: ["app/**/*.rb", "config/*.{yml,json}"]),
        OpenLanes::Apps::ProcessSpec.new(name: "web", start: "y", restart_on: ["src/**/*"], preview: true),
        OpenLanes::Apps::ProcessSpec.new(name: "db", start: "z")
      ])
  end
  let(:watcher) { described_class.new(root:, definition:) }

  after { FileUtils.rm_rf(root) }

  def write(path, text = "x")
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  def touch(path, seconds) = File.utime(Time.now + seconds, Time.now + seconds, File.join(root, path))

  before do
    write("app/models/user.rb")
    write("config/app.yml")
    write("src/main.ts")
    watcher
  end

  it "reports nothing on a quiet tick" do
    expect(watcher.changed).to eq([])
  end

  it "reports only the process whose glob matched an edited file" do
    touch("app/models/user.rb", 5)
    expect(watcher.changed).to eq(["api"])
  end

  it "reports a change once" do
    touch("src/main.ts", 5)
    expect([watcher.changed, watcher.changed]).to eq([["web"], []])
  end

  it "sees a new file, a deleted file and a resize" do
    write("app/new.rb")
    first = watcher.changed
    File.delete(File.join(root, "src/main.ts"))
    second = watcher.changed
    write("config/app.yml", "longer than it was")
    expect([first, second, watcher.changed]).to eq([["api"], ["web"], ["api"]])
  end

  it "reports every process that changed, in declared order" do
    write("src/other.ts")
    write("config/app.json")
    expect(watcher.changed).to eq(%w[api web])
  end

  it "ignores files no glob matches" do
    write("README.md")
    write("config/app.txt")
    expect(watcher.changed).to eq([])
  end
end
