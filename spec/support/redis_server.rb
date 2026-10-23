# frozen_string_literal: true

require "fileutils"
require "socket"
require "tmpdir"

# A throwaway `redis-server` on a spare port, in its own temp directory, that
# a spec may stop and start again on the same port (plan 022). Never the
# Redis on 6379: the user's own data lives there.
#
# Readiness is a real PING through a {OpenLanes::Live::Store}, not a TCP
# connect: some machines accept a connect on every local port.
class RedisServer
  # @return [String, nil] why there is no server to run, for `skip`
  def self.missing = (system("command -v redis-server >/dev/null 2>&1") ? nil : "no redis-server on PATH")

  def initialize
    @dir = Dir.mktmpdir("openlanes-redis-")
    @port = spare_port
  end

  # @return [Integer]
  attr_reader :port

  # @return [String]
  def url = "redis://127.0.0.1:#{@port}/0"

  # Start it. RDB on, so a TERM saves `dump.rdb` and a restart reads it
  # back, as a stock install would; AOF off, as the local install is.
  #
  # @return [self]
  def start
    argv = %W[redis-server --port #{@port} --bind 127.0.0.1 --dir #{@dir} --appendonly no --save] + ["3600 1"]
    @pid = Process.spawn(*argv, out: File::NULL, err: File::NULL)
    wait_until { answers? } or raise "redis-server on #{@port} never answered"
    self
  end

  # Stop it: TERM, which saves the RDB snapshot first.
  #
  # @return [void]
  def stop
    return unless @pid

    Process.kill("TERM", @pid)
    Process.wait(@pid)
    @pid = nil
  rescue Errno::ESRCH, Errno::ECHILD
    @pid = nil
  end

  # What a restart from an empty or lost snapshot looks like.
  #
  # @return [void]
  def wipe = FileUtils.rm_f(File.join(@dir, "dump.rdb"))

  # @return [void]
  def destroy
    stop
    FileUtils.rm_rf(@dir)
  end

  private

  def answers?
    OpenLanes::Live::Store.new(url:, timeout: 0.2).ping
  rescue OpenLanes::Live::Unavailable
    false
  end

  def wait_until(seconds: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (ok = yield)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep(0.05)
    end
    ok
  end

  def spare_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end
end
