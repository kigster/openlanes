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

  DEFAULT_PORT = 6379

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
    # A TCP URL carries the database as its path; a unix URL's path IS the
    # socket, so replacing it would name a socket that does not exist, and
    # the database goes in `?db=N` as redis-rb reads it.
    #
    # @param db [Integer]
    # @param env [Hash, ENV]
    # @return [String]
    # @raise [ArgumentError] when `OPENLANES_TEST_REDIS_URL` names another host
    def url(db, env: ENV)
      base = URI(env.fetch("OPENLANES_TEST_REDIS_URL", DEFAULT))
      raise ArgumentError, "refusing #{base.host}: the suite only uses a Redis on this machine" unless local?(base)

      if base.scheme == "unix"
        base.query = "db=#{db}"
      else
        base.path = "/#{db}"
      end
      base.to_s
    end

    # @param url [String]
    # @return [String, nil] the database the URL names, whichever scheme carries it
    def database(url)
      uri = URI(url)
      return URI.decode_www_form(uri.query.to_s).to_h["db"] if uri.scheme == "unix"

      uri.path.delete_prefix("/")
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
    # The lock is per example, so `:redis` state must be set up per example
    # (`before`, never `before(:all)`): another suite may flush between two
    # examples of one group.
    #
    # @param env [Hash, ENV]
    # @yield
    # @return [Object] the block's value
    def exclusively(env: ENV, &)
      @depth ||= 0
      acquire(env) if @depth.zero?
      # Counted only once the lock is held, so a failed acquisition leaves
      # the depth where it was instead of driving it to -1, which would
      # skip the lock for every later example.
      @depth += 1
      begin
        yield
      ensure
        @depth -= 1
        release if @depth.zero?
      end
    end

    # Where lock files live. `Dir.tmpdir` follows `$TMPDIR`, and sandboxes
    # that each set their own would each lock a different file.
    #
    # @param env [Hash, ENV]
    # @return [String]
    def lock_dir(env: ENV) = env.fetch("OPENLANES_TEST_LOCK_DIR", "/tmp")

    # @param env [Hash, ENV]
    # @return [String] one lock file per Redis server, not per database
    def lock_path(env: ENV)
      base = URI(url(0, env:))
      where = base.scheme == "unix" ? base.path : "loopback-#{base.port || DEFAULT_PORT}"
      File.join(lock_dir(env:), "openlanes-test-redis-#{where.gsub(/[^\w.-]/, "_")}.lock")
    end

    private

    def acquire(env)
      @lock = File.open(lock_path(env:), File::RDWR | File::CREAT, 0o644)
      @lock.flock(File::LOCK_EX)
    rescue Exception # rubocop:disable Lint/RescueException
      @lock&.close
      @lock = nil
      raise
    end

    def release
      @lock.flock(File::LOCK_UN)
      @lock.close
      @lock = nil
    end
  end
end
