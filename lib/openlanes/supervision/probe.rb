# frozen_string_literal: true

module OpenLanes
  module Supervision
    # Whether the process a PID file names is still that process (S2). The
    # number must be alive, its start time must equal the one recorded, and
    # its title must name the role and the project; a file that fails any of
    # the three is a crash, never a target for a signal.
    class Probe
      # What `ps` says about one process.
      Seen = Data.define(:started, :command)

      # `ps -o lstart=` prints a fixed 24 characters in the C locale, such as
      # `Mon Oct 26 01:21:45 2026`; the title follows.
      LINE = /\A\s*(?<started>\w{3} \w{3} [ \d]\d \d\d:\d\d:\d\d \d{4})\s+(?<command>.*?)\s*\z/m

      # Asks `ps` about one pid; empty output when it is gone.
      PS = lambda do |pid|
        out, status = Open3.capture2({ "LC_ALL" => "C" }, "ps", "-o", "lstart=", "-o", "command=", "-p", pid.to_s)
        status.success? ? out : ""
      rescue SystemCallError
        ""
      end

      # @param query [#call] pid in, `ps` output out
      def initialize(query: PS)
        @query = query
      end

      # @param pid [Integer]
      # @return [Seen, nil]
      def seen(pid)
        match = LINE.match(@query.call(pid)) or return
        Seen.new(started: match[:started], command: match[:command])
      end

      # @param pid [Integer]
      # @return [String, nil] its `lstart`, for the process's own PID file
      def started(pid) = seen(pid)&.started

      # @param file [OpenLanes::Supervision::PidFile]
      # @return [Boolean]
      def verified?(file)
        seen = seen(file.pid) or return false
        !file.started.nil? && seen.started == file.started && seen.command.start_with?(file.title)
      end
    end
  end
end
