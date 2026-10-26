# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes status` — the factory at a glance (C1): which of its
    # processes are up, with PIDs, URL and uptime, any that crashed, every
    # `openlanes run`, and the plans by state. It reads PID files and `ps`,
    # never Redis, so it answers when everything else is down.
    class Status < Base
      desc "Which factory processes are up, with PIDs, URL and uptime, and how many plans are in each state"

      # @param file [OpenLanes::Supervision::PidFile]
      # @return [String] the role, and for a run the plans it works
      def self.label(file)
        return file.role unless file.role == Supervision::RUN && !file.plans.empty?

        "#{file.role} #{file.plans.join(",")}"
      end

      # @param options [Hash]
      # @return [void]
      def call(**options)
        quiet?(options)
        $stdout.write(processes)
        $stdout.write(plans(options))
      end

      private

      # @return [String]
      def processes
        entries = Supervision.dir(Dir.pwd).entries
        return "No factory process is running in #{Dir.pwd}.\n" if entries.empty?

        probe = Supervision.probe
        UI.table(entries.map { row(it, probe) }, header: %w[PROCESS PID STATE UP DETAIL])
      end

      # @param entry [OpenLanes::Supervision::PidDir::Entry]
      # @param probe [OpenLanes::Supervision::Probe]
      # @return [Array<String>]
      def row(entry, probe)
        file = entry.file
        return [File.basename(entry.path), "", "unreadable", "", entry.path] unless file

        up = probe.verified?(file)
        uptime = file.uptime
        [self.class.label(file), file.pid.to_s, up ? "up" : "crashed",
         up && uptime ? Supervision::Title.duration(uptime) : "", detail(file)]
      end

      # @param file [OpenLanes::Supervision::PidFile]
      # @return [String]
      def detail(file)
        given_up = file.failed.map { |role, why| "#{role} given up: #{why}" }
        [file.url, *given_up].compact.join("; ")
      end

      # @param options [Hash]
      # @return [String]
      def plans(options)
        tree = Plans.tree(options.fetch(:dir, OpenLanes::PLANS_DIR))
        return "" unless tree.exist?

        counts = tree.subjects.map(&:status).tally
        rows = Plans::STATUSES.filter_map { |status| [status.emoji, status.label, counts[status].to_s] if counts[status] }
        rows.empty? ? "No plans in #{tree.dir}.\n" : UI.table(rows, header: %w[STATE NAME PLANS])
      end
    end
  end
end
