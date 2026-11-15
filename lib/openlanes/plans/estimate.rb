# frozen_string_literal: true

module OpenLanes
  module Plans
    # How long an agent says it still needs (E2), read from what it typed
    # after `--minutes`. A bare number is minutes; `90s`, `20m`, `20 minutes`
    # and `1.5h` are read as written, because an agent asked for minutes
    # answers "1h" often enough that refusing it would send a person a
    # question the agent had in fact answered.
    #
    # Anything else is not guessed at: a guessed estimate is a grant nobody
    # asked for, so the caller is told and may say it again.
    module Estimate
      # A number, then an optional unit.
      FORM = /\A(\d+(?:\.\d+)?)\s*(s|sec|secs|seconds?|m|min|mins|minutes?|h|hr|hrs|hours?)?\z/i

      # Seconds in each unit, by its first letter.
      UNITS = { "s" => 1, "m" => 60, "h" => 3600 }.freeze

      module_function

      # @param text [String, Numeric, nil]
      # @return [Integer, nil] whole seconds; nil when it is not a time above zero
      def seconds(text)
        number, unit = text.to_s.strip.match(FORM)&.captures
        return nil unless number

        seconds = (number.to_f * UNITS.fetch((unit || "m")[0].downcase)).round
        seconds.positive? ? seconds : nil
      end
    end
  end
end
