# frozen_string_literal: true

require "json"
require "socket"
require "time"

module OpenLanes
  module Plans
    # `locked-by.pid` in a plan folder: an agent is working on this plan right
    # now. The folder name never changes for it, because a rename while an
    # agent holds the old path is how its writes land in a directory that no
    # longer exists. The file is git-ignored; it says something true only on
    # the machine that wrote it.
    #
    # @!attribute [r] pid
    #   @return [Integer]
    # @!attribute [r] host
    #   @return [String]
    # @!attribute [r] started_at
    #   @return [Time]
    Lock = Data.define(:pid, :host, :started_at) do
      # @param dir [String] a plan folder
      # @return [String]
      def self.path(dir) = File.join(dir, self::FILENAME)

      # @param dir [String] a plan folder
      # @return [OpenLanes::Plans::Lock, nil] nil when there is no lock, or it cannot be read
      def self.read(dir)
        data = JSON.parse(File.read(path(dir)))
        new(pid: Integer(data.fetch("pid")), host: data.fetch("host").to_s, started_at: Time.iso8601(data.fetch("started_at")))
      rescue Errno::ENOENT, Errno::EISDIR, JSON::ParserError, KeyError, ArgumentError, TypeError
        nil
      end

      # Claim the plan for this process.
      #
      # @param dir [String] a plan folder
      # @param pid [Integer]
      # @param now [Time]
      # @return [OpenLanes::Plans::Lock]
      def self.write(dir, pid: Process.pid, now: Time.now)
        lock = new(pid:, host: Socket.gethostname, started_at: now.utc)
        File.write(path(dir), "#{JSON.generate(lock.to_json_hash)}\n")
        lock
      end

      # @param dir [String] a plan folder
      # @return [void]
      def self.remove(dir) = FileUtils.rm_f(path(dir))

      # @return [Boolean] whether this machine wrote it, so its pid means something here
      def local? = host == Socket.gethostname

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

      # @return [Hash] what the file and the snapshot carry
      def to_json_hash = { pid:, host:, started_at: started_at.utc.iso8601 }
    end

    # The lock file's name, in every plan folder.
    Lock::FILENAME = "locked-by.pid"
  end
end
