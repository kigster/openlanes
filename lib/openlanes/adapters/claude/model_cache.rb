# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Adapters
    class Claude < Base
      # The model list {Catalogue} fetched last, kept on disk between runs so
      # a start-up asks Anthropic once a day rather than once a process, and
      # has something to show when the network is away.
      class ModelCache
        # @param path [String] the file
        # @param now [#call] returns the current `Time`
        def initialize(path, now: -> { Time.now })
          @path = path
          @now = now
        end

        # @return [String]
        attr_reader :path

        # @return [Array(Array<OpenLanes::Adapters::Model>, Integer), Array(nil, nil)]
        #   the cached list and its age in seconds; nothing when the file is
        #   missing, empty or unreadable
        def read
          return [nil, nil] unless File.file?(@path)

          data = JSON.parse(File.read(@path))
          models = Array(data["models"]).map { Model.from_wire(it) }
          return [nil, nil] if models.empty?

          [models, (@now.call - Time.iso8601(data["fetched_at"])).to_i]
        rescue JSON::ParserError, ArgumentError, KeyError, TypeError
          [nil, nil]
        end

        # @param models [Array<OpenLanes::Adapters::Model>]
        # @return [void]
        def write(models)
          FileUtils.mkdir_p(File.dirname(@path))
          wires = models.map { JSON.parse(JSON.generate(it.wire)) }
          File.write(@path, JSON.pretty_generate("fetched_at" => @now.call.utc.iso8601, "models" => wires))
        end

        # @param seconds [Integer]
        # @return [String] "just fetched", "3 minutes old", "2 hours old", "4 days old"
        def self.ago(seconds)
          return "just fetched" if seconds < 60

          size, unit = [[86_400, "day"], [3600, "hour"], [60, "minute"]].find { |(span, _)| seconds >= span }
          n = seconds / size
          "#{n} #{unit}#{"s" unless n == 1} old"
        end
      end
    end
  end
end
