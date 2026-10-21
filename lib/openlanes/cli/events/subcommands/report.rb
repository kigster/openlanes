# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module CLI
    module Events
      # `openlanes events report` — completion, blocks, answers, PRs and usage,
      # read from the durable event log.
      #
      # STDOUT carries the report; the box and progress go to STDERR, so the
      # table or JSON stays pipeable.
      class Report < Base
        desc "Report completion, blocks, time to answer, PR outcomes and usage from the event log"

        option :format, default: "table", values: %w[table json], desc: "table for people, json for scripts"
        option :output,
          aliases: ["-o"],
          desc:    "Write the report here instead of STDOUT; - for STDOUT"

        example [
          "                      # the table",
          "--format json         # for scripts",
          "-o log/events.txt     # to a file"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          quiet?(options)
          root = Dir.pwd
          config = OpenLanes::Config.load(root)
          unless config.events_enabled
            refuse("Events are off. Set `events: { enabled: true }` in #{OpenLanes::Project::FILE} to record runs.", 78)
          end

          log = OpenLanes::Events.log(OpenLanes::Events.dir(root:, config:))
          unless log.exist?
            refuse("No event log at #{log.dir} yet: no run has been recorded since events were enabled.", 66)
          end

          result = OpenLanes::Events.report(log.events, skipped_lines: log.skipped_lines)
          write(Presentation::EventsReport.new(result).render(format: options[:format]), options[:output], options)
        end

        private

        # @return [void]
        def write(text, path, options)
          if path && path != "-"
            path = typed_path(path)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, text)
            success("wrote the events report to [#{path}]") unless quiet?(options)
          else
            $stdout.write(text)
          end
        end
      end
    end
  end
end
