# frozen_string_literal: true

require "etc"
require "open3"
require "time"

module OpenLanes
  module Execution
    # When a process started, so a recovering engine can tell its own agent
    # from a stranger that inherited the pid. Ruby's stdlib has no call for
    # it: Linux answers through `/proc/<pid>/stat`, macOS through
    # `ps -o lstart=`. The engine runs this, never an agent, so the autonomy
    # boundary's withheld commands do not apply.
    module ProcessStart
      module_function

      # @param pid [Integer]
      # @param proc_root [String] where `/proc` is, a fixture in specs
      # @param runner [#capture2] runs `ps`, injected in specs
      # @return [Time, nil] the start time, or nil where it cannot be read
      def of(pid, proc_root: "/proc", runner: Open3)
        return nil unless pid.is_a?(Integer) && pid.positive?

        from_proc(pid, proc_root) || from_ps(pid, runner)
      end

      # Field 22 of `stat` is the start in clock ticks after boot. The command
      # name (field 2) may hold spaces and parentheses, so fields are counted
      # from the last `)`.
      #
      # @api private
      def from_proc(pid, proc_root)
        stat = File.join(proc_root, pid.to_s, "stat")
        uptime = File.join(proc_root, "uptime")
        return nil unless File.file?(stat) && File.file?(uptime)

        ticks = File.read(stat).split(")").last.split[19].to_i
        booted = Time.now - File.read(uptime).split.first.to_f
        booted + (ticks / clock_ticks.to_f)
      rescue SystemCallError, NoMethodError
        nil
      end

      # @api private
      def from_ps(pid, runner)
        out, status = runner.capture2("ps", "-o", "lstart=", "-p", pid.to_s)
        return nil unless status.success?

        text = out.strip
        text.empty? ? nil : Time.parse(text)
      rescue SystemCallError, ArgumentError
        nil
      end

      # @api private
      def clock_ticks
        Etc.sysconf(Etc::SC_CLK_TCK)
      rescue StandardError
        100
      end
    end
  end
end
