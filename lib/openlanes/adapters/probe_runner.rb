# frozen_string_literal: true

require "open3"

module OpenLanes
  module Adapters
    # Runs the local commands a {Base#probe} asks, with a timeout and no
    # prompt. The seam the suite replaces, so a spec never starts a CLI.
    class ProbeRunner
      # Seconds one probe command may take. `claude auth status` answers in
      # well under one; a CLI that hangs on a network call must not hold the
      # probe thread for the whole interval.
      TIMEOUT = 15

      # What one command printed and how it ended.
      #
      # @!attribute [r] stdout
      #   @return [String]
      # @!attribute [r] stderr
      #   @return [String]
      # @!attribute [r] status
      #   @return [Integer, nil] the exit status; nil when it timed out or
      #     could not be started
      Result = Data.define(:stdout, :stderr, :status) do
        # @return [Boolean]
        def ok? = status&.zero? || false

        # @return [Boolean] whether the command never finished
        def timed_out? = status.nil?
      end

      # @param path [String] the `PATH` to search
      # @param timeout [Numeric] seconds
      def initialize(path: ENV.fetch("PATH", ""), timeout: TIMEOUT)
        @path = path
        @timeout = timeout
      end

      # @param executable [String]
      # @return [String, nil] its full path, nil when it is not installed
      def which(executable)
        path.split(File::PATH_SEPARATOR).map { File.join(it, executable) }.find { File.file?(it) && File.executable?(it) }
      end

      # Runs the command with stdin closed. On timeout its process group is
      # killed, so a CLI that forked a helper leaves nothing behind.
      #
      # @param argv [Array<String>]
      # @return [OpenLanes::Adapters::ProbeRunner::Result]
      def call(*argv)
        Open3.popen3({ "NO_COLOR" => "1" }, *argv, pgroup: true) do |stdin, out, err, wait|
          stdin.close
          readers = [Thread.new { out.read }, Thread.new { err.read }]
          wait.join(timeout) ? finished(wait, readers) : killed(wait, readers)
        end
      rescue SystemCallError => e
        Result.new(stdout: "", stderr: e.message, status: nil)
      end

      private

      # @return [String]
      attr_reader :path

      # @return [Numeric]
      attr_reader :timeout

      # @param wait [Process::Waiter]
      # @param readers [Array(Thread, Thread)] stdout's and stderr's
      # @return [OpenLanes::Adapters::ProbeRunner::Result]
      def finished(wait, readers)
        stdout, stderr = readers.map { it.value.to_s }
        Result.new(stdout:, stderr:, status: wait.value.exitstatus)
      end

      # @param wait [Process::Waiter]
      # @param readers [Array(Thread, Thread)]
      # @return [OpenLanes::Adapters::ProbeRunner::Result] a timed-out result
      def killed(wait, readers)
        begin
          Process.kill("KILL", -wait.pid)
        rescue SystemCallError
          nil
        end
        wait.join
        readers.each(&:join)
        Result.new(stdout: "", stderr: "timed out after #{timeout}s", status: nil)
      end
    end
  end
end
