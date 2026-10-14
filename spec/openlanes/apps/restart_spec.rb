# frozen_string_literal: true

require "rbconfig"

# Plan 012 item 8: an edit to one process's `restart_on` files restarts that
# process only. Real processes and a real file; the watcher is polled by
# hand instead of on a timer.
RSpec.describe "Restarting one process of an app" do
  let(:root) { File.realpath(Dir.mktmpdir("openlanes-restart")) }
  let(:server) { File.expand_path("../../fixtures/apps/servers/server.rb", __dir__) }
  let(:registry) { OpenLanes::Apps::Ports.new(path: File.join(root, "ports.json")) }
  let(:published) { [] }
  let(:framings) { [] }
  let(:framing) do
    seen = framings
    Module.new do
      define_singleton_method(:check) do |url, origin:|
        seen << url
        OpenLanes::Apps::Framing.check(url, origin:)
      end
    end
  end
  let(:definition) do
    OpenLanes::Apps::Definition.new(kind: "web",
      processes: [
        OpenLanes::Apps::ProcessSpec.new(name: "api",
          start: "#{RbConfig.ruby} #{server} --name api --port-env PORT_API",
          restart_on: ["api/**/*.rb"]),
        OpenLanes::Apps::ProcessSpec.new(name: "web",
          start: "#{RbConfig.ruby} #{server} --name web --port-env PORT_WEB",
          restart_on: ["web/**/*"],
          preview: true)
      ])
  end
  let(:supervisor) do
    OpenLanes::Apps::Supervisor.new(definition:,
      root:,
      plan: "012.00",
      branch: "b",
      registry:,
      framing:,
      poll: 0.05,
      publisher: ->(status) { published << [status.process, status.state] })
  end
  let(:watcher) { OpenLanes::Apps::Watcher.new(root:, definition:) }

  def edit(path)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, "edited #{rand}")
  end

  def pids = %w[api web].to_h { [it, supervisor.pid(it)] }

  before do
    edit("api/handler.rb")
    edit("web/index.html")
    supervisor.start
    watcher
    published.clear
    framings.clear
  end

  after do
    supervisor.stop
    FileUtils.rm_rf(root)
  end

  it "restarts only the process whose file changed" do
    before = pids
    edit("api/handler.rb")
    watcher.changed.each { supervisor.restart(it) }
    expect(pids["web"]).to eq(before["web"])
    expect(pids["api"]).not_to eq(before["api"])
  end

  it "says restarting, then ready, on the same port" do
    port = supervisor.port("api")
    edit("api/handler.rb")
    watcher.changed.each { supervisor.restart(it) }
    expect([published, supervisor.port("api")]).to eq([[%w[api restarting], %w[api ready]], port])
  end

  it "checks framing again when the preview process restarts, and not for the others" do
    supervisor.restart("api")
    expect(framings).to be_empty
    supervisor.restart("web")
    expect([framings.size, supervisor.preview.framing]).to eq([1, "frame"])
  end

  it "refuses a process the app does not have" do
    expect { supervisor.restart("db") }.to raise_error(ArgumentError, /no process "db"/)
  end
end
