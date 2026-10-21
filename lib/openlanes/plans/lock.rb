# frozen_string_literal: true

require "json"
require "socket"
require "time"

module OpenLanes
  module Plans
    # An agent is working on this plan right now. The folder name never
    # changes for it, because a rename while an agent holds the old path is
    # how its writes land in a directory that no longer exists.
    #
    # The file lives in the runtime state directory ({OpenLanes::Runtime}),
    # named for the plan's ordinal, not in the plan folder: it says something
    # true only on the machine that wrote it, and keyed by ordinal it
    # survives a rename. A `locked-by.pid` an older release left in the
    # folder is still read ({.legacy_path}), and removed with the lock.
    #
    # @!attribute [r] pid
    #   @return [Integer]
    # @!attribute [r] host
    #   @return [String]
    # @!attribute [r] started_at
    #   @return [Time]
    Lock = Data.define(:pid, :host, :started_at) do
      # The plan folder's parent is the plans directory, and its parent the
      # root {Runtime} keys by, so the harness and an agent handed the same
      # `--dir` find one lock.
      #
      # @param dir [String] a plan folder
      # @return [String] `<locks_dir>/<ordinal>.lock`
      def self.path(dir)
        name = File.basename(dir)
        ordinal = Ordinal.from_dirname(name)&.to_s || name
        File.join(Runtime.locks_dir(root: File.dirname(File.expand_path(dir), 2)), "#{ordinal}.lock")
      end

      # @param dir [String] a plan folder
      # @return [String] where releases before the state directory wrote it
      def self.legacy_path(dir) = File.join(dir, self::FILENAME)

      # The one entry point every reader goes through: the state directory
      # first, a legacy file second.
      #
      # @param dir [String] a plan folder
      # @return [OpenLanes::Plans::Lock, nil] nil when there is no lock, or it cannot be read
      def self.read(dir) = parse(path(dir)) || parse(legacy_path(dir))

      # @param file [String]
      # @return [OpenLanes::Plans::Lock, nil]
      def self.parse(file)
        data = JSON.parse(File.read(file))
        new(pid: Integer(data.fetch("pid")), host: data.fetch("host").to_s, started_at: Time.iso8601(data.fetch("started_at")))
      rescue Errno::ENOENT, Errno::EISDIR, JSON::ParserError, KeyError, ArgumentError, TypeError, NoMethodError
        nil
      end
      private_class_method :parse

      # Claim the plan for this process. Creating the file is the claim
      # (`O_EXCL`), so two runs that both saw no lock cannot both write it
      # and have the later one win in silence. A lock this process already
      # holds is rewritten, which is how a pair's partner and a renamed
      # folder find it; one left by a local process that has died is removed
      # and the claim tried once more.
      #
      # @param dir [String] a plan folder
      # @param pid [Integer]
      # @param now [Time]
      # @return [OpenLanes::Plans::Lock]
      # @raise [OpenLanes::Plans::Lock::Held] when another live run holds it
      def self.write(dir, pid: Process.pid, now: Time.now)
        lock = new(pid:, host: Socket.gethostname, started_at: now.utc)
        body = "#{JSON.generate(lock.to_json_hash)}\n"
        legacy = parse(legacy_path(dir))
        raise self::Held, "#{dir} is locked by pid #{legacy.pid} on #{legacy.host}" if legacy&.held_elsewhere? && legacy.pid != pid

        2.times do
          File.open(path(dir), File::WRONLY | File::CREAT | File::EXCL) { it.write(body) }
          return lock
        rescue Errno::EEXIST
          held = read(dir)
          if held&.local? && held.pid == pid
            File.write(path(dir), body)
            return lock
          end
          raise self::Held, "#{dir} is locked by pid #{held.pid} on #{held.host}" if held && !held.stale?
          raise self::Held, "#{dir} has a lock being written or unreadable" if held.nil? && fresh?(dir)

          remove(dir)
        end
        raise self::Held, "#{dir}: another run claimed it first"
      end

      # @param dir [String]
      # @return [Boolean] an unreadable lock young enough to be one another
      #   run has just created and not yet filled
      def self.fresh?(dir)
        Time.now - File.mtime(path(dir)) < self::UNREADABLE_GRACE
      rescue Errno::ENOENT
        false
      end
      private_class_method :fresh?

      # Also clears a legacy file, but only one a dead process on this host
      # left: that is how `resync dirs` keeps clearing old stale locks, and a
      # live or foreign one in the folder is somebody else's claim.
      #
      # @param dir [String] a plan folder
      # @return [void]
      def self.remove(dir)
        FileUtils.rm_f(path(dir))
        legacy = parse(legacy_path(dir))
        FileUtils.rm_f(legacy_path(dir)) if legacy&.stale?
      end

      # @return [Boolean] whether this machine wrote it, so its pid means something here
      def local? = host == Socket.gethostname

      # Written on another host. Held for as long as it exists: never stale,
      # never cleared here, since nothing on this machine can tell it is over.
      #
      # @return [Boolean]
      def foreign? = !local?

      # Only a local lock can be checked; one from another host is never
      # declared dead, since its pid names a process on a machine we cannot see.
      #
      # @return [Boolean]
      def alive?
        return false unless local?

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      # @return [Boolean] written on this machine by a process that is gone
      def stale? = local? && !alive?

      # @return [Boolean] written by this very process, as a pair's partner finds it
      def ours? = local? && pid == Process.pid

      # Another run is in this folder: a live local process that is not this
      # one, or any process on another machine. Such a folder is neither
      # dispatched nor renamed here.
      #
      # @return [Boolean]
      def held_elsewhere? = !ours? && !stale?

      # @return [Hash] what the file and the snapshot carry
      def to_json_hash = { pid:, host:, started_at: started_at.utc.iso8601, foreign: foreign? }
    end

    # The lock file's name in a plan folder, where releases before the
    # runtime state directory wrote it. Read, never written.
    Lock::FILENAME = "locked-by.pid"

    # Seconds an unreadable lock is taken for one being written. Between the
    # `O_EXCL` create and the write the file is empty; older than this, it is
    # debris from a crash and is cleared like a dead pid's.
    Lock::UNREADABLE_GRACE = 5

    class Lock
      # Another live run holds the plan's lock; the claim was not made.
      class Held < OpenLanes::Error; end
    end
  end
end
