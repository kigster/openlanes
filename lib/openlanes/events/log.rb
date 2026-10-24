# frozen_string_literal: true

require "json"

module OpenLanes
  module Events
    # Every node file in a directory, read back as one deduplicated history.
    #
    # Nodes write their own files and never each other's, so merging happens
    # here, at read time. A node that was offline arrives late and is simply
    # read with the rest; nothing is rewritten. A line that is not an event
    # (a torn write, a hand edit) is skipped and counted, never fatal.
    class Log
      attr_reader :dir

      # @param dir [String]
      def initialize(dir:)
        @dir = dir
        @skipped = nil
      end

      # @return [Array<String>] the node files, sorted
      def files = Dir.glob(File.join(dir, "*.jsonl"))

      # @return [Boolean] whether there is anything to read
      def exist? = Dir.exist?(dir)

      # @return [Array<OpenLanes::Events::Event>] unique by `event_id`, oldest first
      def events
        @events ||= begin
          @skipped = 0
          seen = {}
          files.each do |file|
            File.foreach(file, encoding: "UTF-8") do |line|
              next if line.strip.empty?

              event = parse(line) or next
              seen[event.event_id] ||= event
            end
          end
          # Stable on ties: two events in one millisecond keep the order they were written in.
          seen.values.each_with_index.sort_by { |event, index| [event.at, index] }.map(&:first)
        end
      end

      # @return [Integer] lines that were not events
      def skipped_lines
        events
        @skipped
      end

      private

      # @return [OpenLanes::Events::Event, nil]
      def parse(line)
        Event.from_h(JSON.parse(line))
      rescue JSON::ParserError, ArgumentError, KeyError, TypeError, NoMethodError
        @skipped += 1
        nil
      end
    end
  end
end
