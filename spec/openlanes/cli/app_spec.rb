# frozen_string_literal: true

require "open3"
require "rbconfig"
require "socket"

# `openlanes app` as a person types it: the real executable, in a temp
# project, against the fixture server. Redis points at a closed port, so
# nothing here reaches a real one; the registry is a temp file.
RSpec.describe "openlanes app" do
  let(:exe) { File.expand_path("../../../exe/openlanes", __dir__) }
  let(:server) { File.expand_path("../../fixtures/apps/servers/server.rb", __dir__) }
  let(:project) { File.realpath(Dir.mktmpdir("openlanes-app-cli")) }
  let(:ports_file) { File.join(project, "ports.json") }
  let(:env) { { "NO_COLOR" => "1", "OPENLANES_PORTS_FILE" => ports_file, "REDIS_URL" => "redis://127.0.0.1:1/0" } }
  let(:app_yml) do
    <<~YAML
      app:
        kind: web
        processes:
          - name: api
            start: #{RbConfig.ruby} #{server} --name api --port-env PORT_API
          - name: web
            start: #{RbConfig.ruby} #{server} --name web --port-env PORT_WEB
            preview: true
    YAML
  end
  let(:started) { [] }

  before do
    File.write(File.join(project, ".openlanes.yml"), app_yml)
    system("git", "-C", project, "init", "-q", "-b", "kig/012.00-app-runner", exception: true)
  end

  # TERM, as `app stop` sends: a KILL would leave the app's processes
  # running with nobody to stop them.
  after do
    if pid && alive?(pid)
      Process.kill("TERM", pid)
      wait_for { !alive?(pid) }
    end
    FileUtils.rm_rf(project)
  end

  # The `app start` an example spawned, if any.
  def pid = started.first

  def openlanes(*) = Open3.capture3(env, exe, "app", *, chdir: project)

  def alive?(pid)
    Process.kill(0, pid)
    Process.waitpid(pid, Process::WNOHANG).nil?
  rescue Errno::ESRCH, Errno::ECHILD
    false
  end

  def wait_for(seconds = 15)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until yield
      raise "timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end

  def connectable?(port)
    Socket.tcp("127.0.0.1", port, connect_timeout: 0.2).close
    true
  rescue SystemCallError
    false
  end

  def rows(out) = out.lines.drop(1).map(&:split)

  context "with a two-process app" do
    let(:log) { File.join(project, "app.log") }

    before do
      started << Process.spawn(env, exe, "app", "start", chdir: project, out: log, err: log)
      wait_for { rows(openlanes("status").first).size == 2 && rows(openlanes("status").first).all? { connectable?(it[2].to_i) } }
    end

    it "runs both, filed under the plan its branch names, and lists them" do
      out, = openlanes("status")
      expect(rows(out).map { it.first(2) + [it[3]] }).to eq([["012.00", "api", pid.to_s], ["012.00", "web", pid.to_s]])
    end

    it "stops them on app stop, freeing the ports" do
      ports = rows(openlanes("status").first).map { it[2].to_i }
      _, err, status = openlanes("stop", "12")
      wait_for { !alive?(pid) }
      expect([status.success?, err]).to match([true, /Asked #{pid} to stop/])
      expect(ports.map { connectable?(it) }).to eq([false, false])
      expect(openlanes("status")[1]).to include("No app is running on this machine.")
      expect(File.read(log)).to include("web stopped", "api stopped")
    end
  end

  it "refuses a project that declares no app, in one line, writing nothing" do
    File.write(File.join(project, ".openlanes.yml"), "jobs: 2\n")
    _, err, status = openlanes("start")
    expect([status.exitstatus, err.gsub(/[│\s]+/, " ")]).to match([65, /declares no app:, so there is nothing to start/])
    expect(File.exist?(ports_file)).to be(false)
  end

  it "says why an app did not start" do
    File.write(File.join(project, ".openlanes.yml"), "app:\n  processes:\n    - name: web\n      start: exit 9\n")
    _, err, status = openlanes("start")
    expect([status.exitstatus, err.gsub(/[│\s]+/, " ")]).to match([70, /012.00's app did not start: web exited with status 9/])
  end

  it "says there is nothing to stop" do
    _, err, = openlanes("stop", "014")
    expect(err).to include("No app is running for 014.00 on this machine.")
  end

  it "refuses a plan number that is not one" do
    _, err, status = openlanes("stop", "abc")
    expect([status.exitstatus, err]).to match([64, /abc is not a plan number/])
  end
end
