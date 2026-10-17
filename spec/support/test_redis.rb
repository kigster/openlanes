# frozen_string_literal: true

require "tmpdir"
require "uri"

# The one place the suite learns which Redis it may touch.
#
# Two rules, each from a failure:
#
# - Only a Redis on this machine. A shell exporting `REDIS_URL` for a shared
#   or production Redis would otherwise hand it to every spec that resolves
#   the engine's URL, and the `:redis` specs FLUSHDB what they are given.
# - One suite at a time per Redis. Agents in several worktrees run the suite
#   at once, and each one's FLUSHDB wiped the keys another was asserting on,
#   which failed both runs with nothing pointing at the cause.
module TestRedis
  DEFAULT = "redis://localhost:6379/15"

  # The engine's own default, database 0 on localhost, is the developer's live
  # board; this port refuses at once, so a spec that forgot to pick a store
  # fails fast instead of reading or writing it.
  UNREACHABLE = "redis://127.0.0.1:1/0"

  LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

  # Variables a developer's shell or a running engine may export, each of
  # which would steer a spec at the Redis it names.
  INHERITED = %w[REDIS_URL OPENLANES_REDIS_URL].freeze

  class << self
    # Points the inherited variables at {UNREACHABLE}, before any spec runs.
    #
    # @param env [Hash, ENV]
    # @return [void]
    def scrub!(env = ENV)
      INHERITED.each { env.delete(it) }
      env["REDIS_URL"] = UNREACHABLE
    end

    # The URL for one test database on the local Redis.
    #
    # @param db [Integer]
    # @param env [Hash, ENV]
    # @return [String]
    # @raise [ArgumentError] when `OPENLANES_TEST_REDIS_URL` names another host
    def url(db, env: ENV)
      base = URI(env.fetch("OPENLANES_TEST_REDIS_URL", DEFAULT))
      raise ArgumentError, "refusing #{base.host}: the suite only uses a Redis on this machine" unless local?(base)

      base.path = "/#{db}"
      base.to_s
    end

    # @param uri [URI::Generic]
    # @return [Boolean]
    def local?(uri) = uri.scheme == "unix" || LOCAL_HOSTS.include?(uri.host.to_s.downcase)

    # Holds a machine-wide lock on the local Redis while the block runs, so
    # a second suite waits instead of flushing the first one's databases.
    # Re-entrant, because nested `:redis` groups each ask for it; flock locks
    # belong to an open file, and a second open in this process would wait
    # on the first forever.
    #
    # @param env [Hash, ENV]
    # @yield
    # @return [Object] the block's value
    def exclusively(env: ENV)
      @depth ||= 0
      if @depth.zero?
        @lock = File.open(lock_path(env:), File::RDWR | File::CREAT, 0o644)
        @lock.flock(File::LOCK_EX)
      end
      @depth += 1
      yield
    ensure
      @depth -= 1
      if @depth.zero?
        @lock.flock(File::LOCK_UN)
        @lock.close
        @lock = nil
      end
    end

    # @param env [Hash, ENV]
    # @return [String] one lock file per Redis server, not per database
    def lock_path(env: ENV)
      base = URI(url(0, env:))
      where = base.scheme == "unix" ? base.path : "#{base.host}-#{base.port}"
      File.join(Dir.tmpdir, "openlanes-test-redis-#{where.gsub(/[^\w.-]/, "_")}.lock")
    end
  end
end
