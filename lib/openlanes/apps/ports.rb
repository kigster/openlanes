# frozen_string_literal: true

require "fileutils"
require "json"
require "socket"
require "time"

module OpenLanes
  module Apps
    # Every port an app holds on this machine, in one file (plan 012).
    #
    # One file per machine, not per checkout: a worktree isolates files, not
    # ports, and two worktrees of one app asking for 11100 each would both
    # be told yes by anything that only looked at its own checkout.
    #
    # A port is reserved under an exclusive `flock` and also probed, both by
    # connecting to it and by binding it: something that never registered
    # here (a dev server started by hand, the control room) still holds it.
    # The probe and the spawn that follows it leave a gap no lock covers, so
    # {Supervisor} retries a start that lost that race.
    #
    # An entry belongs to the pid that reserved it. Once that process is
    # gone the entry counts as free, which is how a runner killed with KILL
    # gives its ports back without anyone cleaning up after it.
    class Ports
      # The first port an app is given (M12).
      FLOOR = 11_100

      # The last. Not configurable: per-plan ranges are a non-goal.
      CEILING = 11_999

      # Overrides where the registry lives; the suite and the Cypress run
      # point it at a temp file.
      FILE_ENV = "OPENLANES_PORTS_FILE"

      # Every port in the range is held.
      class Exhausted < Error; end

      class << self
        # `$OPENLANES_PORTS_FILE`, else `${XDG_STATE_HOME:-~/.local/state}/openlanes/ports.json`.
        #
        # @param env [Hash]
        # @return [String]
        def default_path(env = ENV)
          return env[FILE_ENV] unless env[FILE_ENV].to_s.strip.empty?

          state = env["XDG_STATE_HOME"].to_s.strip
          File.join(state.empty? ? File.expand_path("~/.local/state") : state, "openlanes", "ports.json")
        end

        # Nothing answers on the port and it can be bound on 127.0.0.1. The
        # connect catches a listener on another address, which macOS lets a
        # SO_REUSEADDR bind on 127.0.0.1 sit beside.
        #
        # @param port [Integer]
        # @return [Boolean]
        def free?(port)
          return false if answering?(port)

          TCPServer.new(Status::HOST, port).close
          true
        rescue SystemCallError
          false
        end

        # @param port [Integer]
        # @return [Boolean]
        def answering?(port)
          Socket.tcp(Status::HOST, port, connect_timeout: 0.2).close
          true
        rescue SystemCallError, IOError
          false
        end

        # @param pid [Integer]
        # @return [Boolean]
        def alive?(pid)
          Process.kill(0, pid.to_i)
          true
        rescue Errno::ESRCH, RangeError
          false
        rescue Errno::EPERM
          true
        end
      end

      # @param path [String] the registry file
      # @param owner [Integer] whose reservations these are
      # @param floor [Integer]
      # @param ceiling [Integer]
      # @param free [#call] a port to whether it can be taken
      # @param alive [#call] a pid to whether it still runs
      def initialize(path: self.class.default_path, owner: Process.pid, floor: FLOOR, ceiling: CEILING,
        free: self.class.method(:free?), alive: self.class.method(:alive?))
        @path = path
        @owner = owner
        @floor = floor
        @ceiling = ceiling
        @free = free
        @alive = alive
      end

      # @return [String]
      attr_reader :path

      # The lowest port at or above the floor that nobody holds.
      #
      # @param root [String] the checkout the app runs in
      # @param plan [String]
      # @param process [String]
      # @return [Integer]
      # @raise [OpenLanes::Apps::Ports::Exhausted]
      def reserve(root:, plan:, process:)
        locked do |entries|
          port = (@floor..@ceiling).find { !entries.key?(it) && @free.call(it) }
          raise Exhausted, "every port from #{@floor} to #{@ceiling} is taken" unless port

          entries[port] = { "owner" => @owner, "root" => root, "plan" => plan, "process" => process, "at" => Time.now.utc.iso8601 }
          port
        end
      end

      # @param port [Integer]
      # @return [void]
      def release(port) = locked { it.delete(port.to_i) }

      # Everything one process holds.
      #
      # @param pid [Integer]
      # @return [Array<Integer>] the ports released
      def release_owner(pid = @owner)
        locked do |entries|
          entries.select { |_, entry| entry["owner"] == pid }.keys.tap { |ports| ports.each { entries.delete(it) } }
        end
      end

      # Every live reservation, by port.
      #
      # @return [Hash{Integer => Hash}] `owner`, `root`, `plan`, `process`, `at`
      def entries = locked(&:dup)

      private

      # Read, hand the live entries to the block, write back what it left.
      # Dead owners' entries are dropped on the way.
      #
      # @yieldparam entries [Hash{Integer => Hash}]
      # @return [Object] the block's value
      def locked
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, File::RDWR | File::CREAT, 0o644) do |file|
          file.flock(File::LOCK_EX)
          entries = parse(file.read).select { |_, entry| @alive.call(entry["owner"]) }
          yield(entries).tap do
            file.rewind
            file.truncate(0)
            file.write(JSON.pretty_generate(entries.sort.to_h { [it.first.to_s, it.last] }))
          end
        end
      end

      # @return [Hash{Integer => Hash}]
      def parse(text)
        data = text.strip.empty? ? {} : JSON.parse(text)
        data.is_a?(Hash) ? data.to_h { |port, entry| [port.to_i, entry] }.select { |_, entry| entry.is_a?(Hash) } : {}
      rescue JSON::ParserError
        # A file somebody broke by hand is a registry with nothing in it; the
        # probes still keep a taken port from being handed out twice.
        {}
      end
    end
  end
end
