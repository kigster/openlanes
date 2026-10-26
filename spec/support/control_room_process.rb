# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "redis-client"
require "socket"
require "tmpdir"

# Real `exe/openlanes` processes over a real Redis, for the integration specs
# that prove what unit specs cannot: that the engine and the API server, as
# separate processes, agree through Redis alone.
#
# Every wait is a deadline, never a sleep: a sleep long enough for a slow CI
# machine is a sleep wasted on every fast one, and a sleep short enough for a
# fast one flakes on the slow.
#
# A `claude` that exits 1 is put first on PATH, so a fixture that drifts into
# a state an agent handles fails the attempt instead of spending tokens.
class ControlRoomProcess
  EXE = File.expand_path("../../exe/openlanes", __dir__)
  DIST = File.expand_path("../../web/dist/index.html", __dir__)
  REMOTE = "git@github.com:example-org/control-room-fixture.git"

  # Raised when a deadline passes before the condition held.
  class Timeout < StandardError; end

  # One SSE event as the page reads it.
  Event = Data.define(:name, :id, :data)

  # A live `text/event-stream`, read on a thread into a queue.
  class Stream
    # @param uri [URI::HTTP]
    # @param headers [Hash{String => String}]
    def initialize(uri, headers)
      @events = Queue.new
      @thread = Thread.new { read(uri, headers) }
    end

    # Events until the block returns truthy for one, which is returned.
    #
    # @param deadline [Float] seconds
    # @return [Event]
    def wait_for(deadline: 10)
      stop = monotonic + deadline
      loop do
        left = stop - monotonic
        raise Timeout, "no matching event within #{deadline}s" if left <= 0

        event = @events.pop(timeout: left)
        raise Timeout, "no matching event within #{deadline}s" if event.nil?
        raise event if event.is_a?(Exception)
        return event if yield(event)
      end
    end

    # @return [void]
    def close = @thread.kill.join(1)

    private

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def read(uri, headers)
      Net::HTTP.start(uri.host, uri.port, read_timeout: 60) do |http|
        http.request(Net::HTTP::Get.new(uri, headers)) do |response|
          buffer = +""
          response.read_body do |chunk|
            buffer << chunk
            while (frame = buffer.slice!(/\A.*?\n\n/m))
              event = parse(frame)
              @events << event if event
            end
          end
        end
      end
    rescue IOError, SystemCallError => e
      @events << e
    end

    def parse(frame)
      fields = Hash.new { |table, key| table[key] = +"" }
      frame.each_line(chomp: true) do |line|
        key, value = line.split(":", 2)
        fields[key] << value.delete_prefix(" ") if value && !key.empty?
      end
      return unless fields.key?("event")

      Event.new(name: fields["event"], id: fields["id"], data: JSON.parse(fields["data"]))
    end
  end

  # The Redis URL for one database, so each spec owns its keys.
  #
  # @param db [Integer]
  # @return [String]
  def self.redis_url(db) = TestRedis.url(db)

  # Through the gem the engine itself uses, not `redis-cli`: CI's Ruby image
  # has a Redis service beside it but no `redis-cli` on PATH, and a check
  # that cannot run would skip every example there without a word.
  #
  # @param url [String]
  # @return [Boolean]
  def self.redis?(url)
    client = RedisClient.config(url:).new_client
    client.call("PING") == "PONG"
  rescue RedisClient::Error
    false
  ensure
    client&.close
  end

  # @return [Boolean]
  def self.dist? = File.file?(DIST)

  # The harness finds the engine's own API server, a child in a process group
  # of its own, by the port it listens on. Without `lsof` that lookup came
  # back nil and `kill(:server)` died on a TypeError that named nothing.
  #
  # @param path [String] the PATH to search
  # @return [Boolean]
  def self.lsof?(path = ENV.fetch("PATH", ""))
    path.split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, "lsof")) }
  end

  # Why an integration spec cannot run here, or nil when it can. Cheapest
  # check first, so a missing tool is reported without dialing Redis.
  #
  # @param url [String]
  # @param path [String]
  # @return [String, nil] the reason to skip
  def self.unmet(url, path: ENV.fetch("PATH", ""))
    return "lsof is not on PATH: the harness finds the API server by its port" unless lsof?(path)
    return "web/dist is missing: run just web-build first" unless dist?
    return "no Redis answers at #{url}" unless redis?(url)

    nil
  end

  # Databases below this are left alone: {#stop_all} runs FLUSHDB, and a
  # laptop's own Redis keeps its data in the low ones (openlanes itself
  # defaults to 0), so a harness pointed there would wipe it.
  FIRST_TEST_DATABASE = 10

  # @param url [String]
  # @return [Boolean] whether the URL names a database this harness may flush
  def self.dedicated?(url)
    db = TestRedis.database(url).to_s
    db.match?(/\A\d+\z/) && db.to_i >= FIRST_TEST_DATABASE
  end

  # @param root [String] the checkout, holding `.plans`
  # @param redis_url [String]
  # @param port [Integer, nil] picked free when nil
  # @raise [ArgumentError] when the URL names no database {.dedicated?} allows
  def initialize(root:, redis_url:, port: nil)
    unless self.class.dedicated?(redis_url)
      raise ArgumentError, "refusing #{redis_url}: stop_all flushes it; use a database >= #{FIRST_TEST_DATABASE}"
    end

    @root = root
    @redis_url = redis_url
    @port = port || free_port
    @pids = {}
    @ports = [@port]
    @bin = Dir.mktmpdir("openlanes-fake-claude")
    File.write(File.join(@bin, "claude"), "#!/bin/sh\necho \"$PWD\" >> '#{calls_log}'\nexit 1\n")
    File.chmod(0o755, File.join(@bin, "claude"))
  end

  # @return [String, Integer]
  attr_reader :root, :port

  # How many times an engine ran `claude`, every one of them the fake: a spec
  # whose engine starts agents asserts this is positive, which proves the
  # fake, not a real and paid `claude`, is what the engine found on PATH.
  #
  # @return [Integer]
  def agent_calls = File.file?(calls_log) ? File.readlines(calls_log).size : 0

  # Turn a directory into a git checkout whose repository key is {REMOTE}, so
  # two of them are one repository to Redis. Nothing reaches the network.
  #
  # It also sets `desired_codebase_quality:`, because an engine with the key
  # unset and no TTY to ask on holds every plan back until someone answers,
  # and a spec waiting on a claim would wait out its deadline instead.
  #
  # @param root [String]
  # @return [String] root
  def self.checkout(root)
    system("git", "init", "-q", root, exception: true)
    system("git", "-C", root, "remote", "add", "origin", REMOTE, exception: true)
    File.write(File.join(root, ".openlanes.yml"), "desired_codebase_quality: high\n")
    root
  end

  # `openlanes start`, the factory, which starts its own API server beside it.
  #
  # @param web_port [Integer] where that server listens: {#port} by default,
  #   another one when a server started by {#start_server} already holds it,
  #   since a factory whose own page did not come up refuses to start
  # @return [Integer] the engine's pid
  def start_engine(web_port: port)
    @ports |= [web_port]
    @pids[:engine] = spawn("engine",
      "start",
      "--no-open",
      "--port",
      web_port.to_s,
      "--redis-url",
      @redis_url,
      "--isolation",
      "shared")
    wait_until(deadline: 30) { healthy?(web_port) }
    @pids[:engine]
  end

  # `openlanes web` on its own, as after the engine's server was killed.
  #
  # @return [Integer] the server's pid
  def start_server
    @pids[:server] = spawn("server", "web", "--no-open", "--port", port.to_s, "--redis-url", @redis_url)
    wait_until(deadline: 30) { healthy? }
    @pids[:server]
  end

  # @param which [Symbol] :engine or :server
  # @param signal [String]
  # @return [void]
  def kill(which, signal: "KILL")
    pid = which == :server ? server_pid : @pids.fetch(which)
    raise ArgumentError, "no server listens on #{port}" unless pid

    Process.kill(signal, pid)
    reap(pid)
    @pids.delete(which)
  end

  # Polls the block until it returns truthy.
  #
  # @param deadline [Float] seconds
  # @return [Object] the block's value
  def wait_until(deadline:)
    stop = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline
    loop do
      value = yield
      return value if value
      raise Timeout, "condition not met within #{deadline}s; logs in #{log_dir}" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) > stop

      Thread.pass
      IO.select(nil, nil, nil, 0.05)
    end
  end

  # @return [Net::HTTPResponse]
  def get(path) = http { it.request(Net::HTTP::Get.new(path, headers)) }

  # @return [Net::HTTPResponse]
  def post(path, json)
    request = Net::HTTP::Post.new(path, headers.merge("Content-Type" => "application/json", "X-CSRF-Token" => csrf))
    request.body = JSON.generate(json)
    http { it.request(request) }
  end

  # @param path [String]
  # @return [Stream]
  def sse(path, last_event_id: nil)
    extra = last_event_id ? { "Last-Event-ID" => last_event_id } : {}
    (@streams ||= []) << Stream.new(URI("http://127.0.0.1:#{port}#{path}"), headers.merge(extra))
    @streams.last
  end

  # Stops every process this harness started and flushes its Redis database.
  #
  # @return [void]
  def stop_all
    @streams&.each(&:close)
    # Every signal first, then every reap: the server is the engine's child,
    # and stays a zombie until the engine is gone and launchd reaps it.
    pids = [*@ports.map { listener(it) }, *@pids.values].compact.uniq
    pids.each { signal("KILL", it) }
    pids.each { reap(it) } # rubocop:disable Style/CombinableLoops
    @pids.clear
    redis("FLUSHDB")
    FileUtils.rm_rf(@bin)
  end

  # @return [String]
  def log_dir = File.join(root, "log")

  # A free TCP port on 127.0.0.1, for a second server beside {#port}.
  #
  # @return [Integer]
  def self.free_port = TCPServer.open("127.0.0.1", 0) { it.addr[1] }

  # One Redis command against this harness's database.
  #
  # @param command [Array<String>]
  # @return [Object] what Redis answered
  def redis(*command)
    client = RedisClient.config(url: @redis_url).new_client
    client.call(*command)
  ensure
    client&.close
  end

  private

  def headers = { "Host" => "127.0.0.1:#{port}" }

  def csrf = @csrf = JSON.parse(get("/api/session").body).fetch("csrf")

  def http(&) = Net::HTTP.start("127.0.0.1", port, open_timeout: 2, read_timeout: 10, &)

  def healthy?(on = port)
    Net::HTTP.start("127.0.0.1", on, open_timeout: 2, read_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new("/healthz", "Host" => "127.0.0.1:#{on}")).is_a?(Net::HTTPOK)
    end
  rescue SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout
    false
  end

  # The process listening on the port: the engine's own server is its child,
  # in a process group of its own, so the harness never held its pid.
  def server_pid = @pids[:server] || listener(port)

  # @param on [Integer]
  # @return [Integer, nil] the pid listening on that port
  def listener(on)
    pid = `lsof -nP -t -iTCP:#{on} -sTCP:LISTEN 2>/dev/null`.split.first&.to_i
    pid&.positive? ? pid : nil
  end

  def calls_log = File.join(@bin, "calls.log")

  # The fake goes first on PATH twice over. The executor starts an agent in
  # Bundler's unbundled environment, whose PATH is BUNDLER_ORIG_PATH, the
  # PATH from before `bundle exec`; with only PATH set, every agent the
  # engine started found the real `claude` and ran it, at a model's price.
  def spawn(name, *)
    FileUtils.mkdir_p(log_dir)
    path = "#{@bin}:#{ENV.fetch("BUNDLER_ORIG_PATH", ENV.fetch("PATH"))}"
    env = { "PATH" => path, "BUNDLER_ORIG_PATH" => path, "OPENLANES_REDIS_URL" => @redis_url, "NO_COLOR" => "1",
            "CI" => "1" }
    Process.spawn(env,
      EXE,
      *,
      chdir:  root,
      pgroup: true,
      in:     File::NULL,
      out:    File.join(log_dir, "#{name}.out"),
      err:    [:child, :out])
  end

  def reap(pid)
    Process.wait(pid)
  rescue Errno::ECHILD
    wait_until(deadline: 10) { !alive?(pid) }
  end

  def signal(name, pid)
    Process.kill(name, pid)
  rescue Errno::ESRCH
    nil
  end

  # A killed server whose parent, the engine, has not reaped it is a zombie:
  # gone for every purpose here, though `kill 0` still finds it.
  def alive?(pid)
    state = `ps -o stat= -p #{pid}`.strip
    !state.empty? && !state.start_with?("Z")
  end

  def free_port = self.class.free_port
end
