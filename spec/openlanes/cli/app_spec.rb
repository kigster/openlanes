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

  # The rest run in this process, so their paths count; none of them
  # leaves anything running.
  describe "in process" do
    around do |example|
      saved = ENV.to_h.slice("OPENLANES_PORTS_FILE", "REDIS_URL", "NO_COLOR")
      ENV.update(env)
      traps = %w[INT TERM].to_h { [it, Signal.trap(it, "DEFAULT")] }
      Dir.chdir(project) { example.run }
    ensure
      traps.each { |name, handler| Signal.trap(name, handler) }
      env.each_key { ENV.delete(it) }
      ENV.update(saved)
    end

    def command(klass, **)
      out = CapturedStream.new
      err = CapturedStream.new
      original = [$stdout, $stderr]
      $stdout, $stderr = out, err
      status = 0
      begin
        klass.new.call(**klass.default_params, **)
      rescue SystemExit => e
        status = e.status
      ensure
        $stdout, $stderr = original
      end
      [strip_ansi(out.string), strip_ansi(err.string).gsub(/[│\s]+/, " "), status]
    end

    def registry = OpenLanes::Apps::Ports.new(path: ports_file, free: ->(_) { true })

    it "refuses a project that declares no app, in one line, writing nothing" do
      File.write(File.join(project, ".openlanes.yml"), "jobs: 2\n")
      _, err, status = command(OpenLanes::CLI::App::Start)
      expect([status, err]).to match([65, /declares no app:, so there is nothing to start/])
      expect(File.exist?(ports_file)).to be(false)
    end

    it "refuses an app: it cannot read, naming the file" do
      File.write(File.join(project, ".openlanes.yml"), "app:\n  processes: []\n")
      _, err, status = command(OpenLanes::CLI::App::Start)
      expect([status, err]).to match([65, /app.processes: must be a list/])
    end

    it "says why an app did not start, filed under the plan its branch names" do
      File.write(File.join(project, ".openlanes.yml"), "app:\n  processes:\n    - name: web\n      start: exit 9\n")
      _, err, status = command(OpenLanes::CLI::App::Start)
      expect([status, err]).to match([70, /012.00's app did not start: web exited with status 9/])
      expect(err).to include("Redis at redis://127.0.0.1:1/0", "the app runs, but the Preview tab will not hear of it")
    end

    it "runs a named plan in the project root when it has no worktree" do
      FileUtils.mkdir_p(File.join(project, ".plans", OpenLanes::Plans.plan_dirname("014.00", OpenLanes::Plans.status(:planned), "next")))
      File.write(File.join(project, ".openlanes.yml"), "app:\n  processes:\n    - name: web\n      start: exit 2\n")
      _, err, = command(OpenLanes::CLI::App::Start, plan: "14")
      expect(err).to include("014.00's app did not start", "in #{project} (kig/012.00-app-runner)")
    end

    it "refuses a plan the project does not have" do
      FileUtils.mkdir_p(File.join(project, ".plans"))
      _, err, status = command(OpenLanes::CLI::App::Start, plan: "99")
      expect([status, err]).to match([66, /No plan 099.00/])
    end

    it "says there is nothing to stop, or to list" do
      _, stop, = command(OpenLanes::CLI::App::Stop, plan: "014")
      _, status, = command(OpenLanes::CLI::App::Status)
      expect([stop, status]).to match([/No app is running for 014.00 on this machine/, /No app is running on this machine/])
    end

    it "refuses a plan number that is not one" do
      _, err, status = command(OpenLanes::CLI::App::Stop, plan: "abc")
      expect([status, err]).to match([64, /abc is not a plan number/])
    end

    it "lists every reservation as a table on STDOUT" do
      registry.reserve(root: "/w/main", plan: "012.00", process: "web")
      registry.reserve(root: "/w/main", plan: "012.00", process: "api")
      out, = command(OpenLanes::CLI::App::Status)
      expect(out.lines.map(&:split)).to eq([%w[PLAN PROCESS PORT PID CHECKOUT],
                                            ["012.00", "api", "11101", Process.pid.to_s, "/w/main"],
                                            ["012.00", "web", "11100", Process.pid.to_s, "/w/main"]])
    end

    it "asks the process holding a plan's ports to stop, and only that plan's" do
      sleeper = Process.spawn("sleep", "30")
      OpenLanes::Apps::Ports.new(path: ports_file, owner: sleeper, free: ->(_) { true }).reserve(root: "/w", plan: "012.00", process: "web")
      registry.reserve(root: "/w", plan: "014.00", process: "web")
      _, err, = command(OpenLanes::CLI::App::Stop, plan: "12")
      Process.wait(sleeper)
      expect([err, $?.termsig]).to match([/Asked #{sleeper} to stop/, Signal.list["TERM"]])
    ensure
      Process.kill("KILL", sleeper) if sleeper && alive?(sleeper)
    end
  end
end
