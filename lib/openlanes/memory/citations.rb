# frozen_string_literal: true

module OpenLanes
  module Memory
    # The lessons an agent's report says it applied (decision C5).
    #
    # Only ids the invocation was offered count. Matching any `L-\d+` in the
    # text would credit a lesson for turning up in a diff, a log line or a
    # plan's notes, and charge none of that to the lessons the agent was
    # actually shown; matching the offered ids as whole tokens cannot.
    module Citations
      # Characters that may sit inside a lesson id ({Lesson::ID}), so one may
      # not touch an id on either side without making it a longer token. A
      # `.` after an id ends it only when no id character follows, so
      # `L-0007.` at the end of a sentence counts and `L-0007.1` does not.
      INSIDE = "A-Za-z0-9_\\-"

      module_function

      # @param text [String, nil] what the agent reported
      # @param offered [Array<String>] the ids its prompt carried
      # @return [Array<String>] the offered ids the text names, each once, in offered order
      def in(text, offered:)
        return [] if text.to_s.empty?

        offered.uniq.select { text.match?(pattern(it)) }
      end

      # @param id [String]
      # @return [Regexp]
      def pattern(id) = /(?<![#{INSIDE}.])#{Regexp.escape(id)}(?![#{INSIDE}]|\.[#{INSIDE}])/
    end
  end
end
