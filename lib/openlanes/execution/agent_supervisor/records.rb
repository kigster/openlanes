# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

module OpenLanes
  module Execution
    class AgentSupervisor
      # What it leaves on disk for the engine: its PID file and the CLI's
      # exit status, each written atomically so a reader never sees half.
      Records = Data.define(:options) do
        # The same JSON as every other PID file, so `openlanes status` lists
        # it and {Supervision::Probe} verifies it.
        #
        # @param child [Integer] the CLI's pid
        # @return [void]
        def pid_file(child)
          file = { role: ROLE, pid: ::Process.pid, started:, root: options.root, plans: [options.plan],
                   agent: options.agent, child:, output: options.output, status: options.status }
          write(options.pid_file, JSON.pretty_generate(file.compact))
        end

        # @param ended [Hash{Symbol => Integer}] `exitstatus:` or `termsig:`
        # @return [void]
        def status(ended) = write(options.status, JSON.generate(ended))

        private

        # @return [String, nil] this process's start time, as `ps` gives it
        def started
          out, status = Open3.capture2({ "LC_ALL" => "C" }, "ps", "-o", "lstart=", "-p", ::Process.pid.to_s)
          status.success? ? out.strip : nil
        rescue SystemCallError
          nil
        end

        # @param path [String]
        # @param text [String]
        # @return [void]
        def write(path, text)
          FileUtils.mkdir_p(File.dirname(path))
          File.write("#{path}.tmp", text)
          File.rename("#{path}.tmp", path)
        end
      end
    end
  end
end
