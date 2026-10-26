# frozen_string_literal: true

module OpenLanes
  module Supervision
    # The operating system, as far as supervision touches it: starting a
    # process, asking whether it has ended, signalling it, and the time. One
    # value, so the supervisor, the stopper and a `--background` start take
    # the same seam, and a spec replaces all four at once.
    #
    # @!attribute [r] spawner
    #   @return [#spawn] {Spawner::System} outside the suite
    # @!attribute [r] waiter
    #   @return [#call] pid in; nil while it runs, its status (or :gone) once ended
    # @!attribute [r] signaller
    #   @return [#call] signal name and target in; a negative target is a process group
    # @!attribute [r] clock
    #   @return [#monotonic, #sleep]
    Host = Data.define(:spawner, :waiter, :signaller, :clock) do
      # @param spawner [#spawn]
      # @param waiter [#call]
      # @param signaller [#call]
      # @param clock [#monotonic, #sleep]
      def initialize(spawner: Spawner::System, waiter: Host::WAITER, signaller: Host::SIGNALLER, clock: OpenLanes::Clock::System)
        super
      end
    end

    class Host
      # Non-blocking, and reaps what it finds ended. A pid that is not this
      # process's child is :gone.
      WAITER = lambda do |pid|
        ::Process.wait2(pid, ::Process::WNOHANG)&.last
      rescue Errno::ECHILD
        :gone
      end

      # A target already gone, or not ours to signal, is nothing to report.
      SIGNALLER = lambda do |signal, target|
        ::Process.kill(signal, target)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      # This machine.
      SYSTEM = new

      # The exit statuses a command refuses with on purpose (sysexits.h).
      REFUSALS = (64..78)

      # Whether a process ended of its own accord: exit 0, or a refusal.
      # A signal, or an exit such as the 1 an unhandled error ends in, is a
      # crash, even from a process that died before it could write a PID file.
      #
      # @param status [Process::Status, Symbol] what {WAITER} returned
      # @return [Boolean]
      def self.on_purpose?(status)
        return false unless status.respond_to?(:exitstatus) && status.exitstatus

        status.exitstatus.zero? || REFUSALS.cover?(status.exitstatus)
      end

      # @param status [Process::Status, Symbol] what {WAITER} returned
      # @return [String] `exit 1`, `signal 9`, or `gone`
      def self.describe(status)
        return status.to_s unless status.respond_to?(:signaled?)

        status.signaled? ? "signal #{status.termsig}" : "exit #{status.exitstatus}"
      end
    end
  end
end
