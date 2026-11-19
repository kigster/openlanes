# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What a session said last, clipped for a one-line report.
      module Said
        # How much of what the agent said survives into a one-line report.
        LIMIT = 300

        module_function

        # @param transcript [OpenLanes::Execution::Transcript]
        # @return [String] the error when it failed, else the last few plain lines
        def of(transcript)
          text = (transcript.failed? ? transcript.error : transcript.plain.last(3).join(" ")).to_s.strip
          return "said nothing" if text.empty?

          text.length > LIMIT ? "#{text[0, LIMIT - 1]}..." : text
        end
      end
    end
  end
end
