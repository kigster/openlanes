# frozen_string_literal: true

module OpenLanes
  module Memory
    # How often each lesson was offered and cited on this project, read from
    # the event log (decision C5). There is no `usage.json`: the log is the
    # only record, and with the log off there is no count at all, which is
    # why {.read} answers nil rather than a table of zeros that would read as
    # "every lesson was ignored".
    module Uptake
      module_function

      # @param root [String] the project root
      # @param config [OpenLanes::Config]
      # @return [Hash{String => OpenLanes::Events::LessonUsage}, nil] by lesson id; nil when events are off
      def read(root:, config: Config.load(File.expand_path(root)))
        return nil unless config.events_enabled

        root = File.expand_path(root)
        log = Events.log(Events.dir(root:, config:))
        # The project name the sink stamps, so a shared log directory counts this project alone.
        Events.lesson_usage(log.exist? ? log.events : [], project: config.project || File.basename(root))
      end
    end
  end
end
