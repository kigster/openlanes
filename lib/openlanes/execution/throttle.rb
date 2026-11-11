# frozen_string_literal: true

module OpenLanes
  module Execution
    # A provider that says "not now" (plan 060.00, item 4): a rate limit
    # (HTTP 429) or an overload (529), as opposed to an invocation that failed
    # at its own work.
    #
    # Before this, either one ended the invocation as a failed attempt. With
    # `jobs: 7` a single 429 burst failed seven plans at once, each of which
    # then spent a round relearning where it had been. The {Executor} now asks
    # {.detect} of every invocation that failed, waits as {Backoff} says, and
    # starts the agent again inside the same attempt.
    #
    # Detection reads the words the CLI printed, because that is all five
    # adapters have in common: none of them hands on a status code as a field.
    # Only an invocation that already failed is read, so an agent that wrote
    # "429" in a sentence and finished its work is never taken for throttled.
    module Throttle
      # What a rate limit looks like in a CLI's last words. "usage limit" is a
      # subscription's window running out: hours away, so {Backoff} gives up
      # on it, but it gives up saying "rate limited" rather than "claude
      # reported".
      RATE_LIMIT = /\b429\b|rate[ _-]?limit|too many requests|resource[ _]exhausted|usage limit/i

      # What an overloaded provider looks like.
      OVERLOADED = /\b529\b|overloaded|service unavailable/i

      # "retry-after: 30", "retry_after":12.5, "Retry-After 7".
      RETRY_AFTER = /retry[ _-]?after["':=\s]+(\d+(?:\.\d+)?)/i

      # "try again in 20s", "Please retry in 34.2 seconds", "retry in 2 minutes".
      RETRY_IN = /(?:try again|retry(?:ing)?) in (\d+(?:\.\d+)?)\s*(ms|milliseconds?|s|secs?|seconds?|m|mins?|minutes?|h|hours?)\b/i

      # How many of the CLI's plain lines are read when it reported no error
      # of its own: its last words, not the whole run, since an agent working
      # on rate-limiting code prints "429" all afternoon.
      LAST_WORDS = 3

      module_function

      # @param status [Process::Status, #success?] how the process ended
      # @param transcript [#failed?, #error, #plain] what it said
      # @return [OpenLanes::Execution::Throttle::Limit, nil] the limit the
      #   invocation ended on, nil when it succeeded or failed at anything else
      def detect(status, transcript)
        return nil if status.success? && !transcript.failed?

        text = last_words(transcript)
        kind = kind_of(text) or return nil
        Limit.new(kind:, retry_after: retry_after(text), detail: text.lines.first.to_s.strip[0, 200])
      end

      # @param text [String]
      # @return [Symbol, nil] :rate_limit, :overloaded, or nil for neither
      def kind_of(text)
        return :rate_limit if RATE_LIMIT.match?(text)

        :overloaded if OVERLOADED.match?(text)
      end

      # @param text [String]
      # @return [Float, nil] seconds the provider asked for, when it said
      def retry_after(text)
        if (asked = RETRY_AFTER.match(text))
          asked[1].to_f
        elsif (asked = RETRY_IN.match(text))
          asked[1].to_f * seconds_in(asked[2].downcase)
        end
      end

      # @param unit [String] a unit {RETRY_IN} matched, lower case
      # @return [Numeric] seconds in one of it
      def seconds_in(unit)
        if unit.start_with?("ms", "mil") then 0.001
        elsif unit.start_with?("m") then 60
        elsif unit.start_with?("h") then 3600
        else
          1
        end
      end

      # What a session is told when it is carried on after the wait. It ended
      # mid-step on an error it never saw, so without this it resumes with no
      # idea why its last request went nowhere.
      #
      # @param limit [OpenLanes::Execution::Throttle::Limit]
      # @return [String]
      def carry_on(limit)
        what = limit.kind == :overloaded ? "was overloaded when it got" : "rate limited"
        <<~PROMPT
          Your provider #{what} your last request, and the harness paused you
          until now. Nothing else changed: this is the same session and the
          same round.

          Carry on from the step you were on, as your original instructions
          say, and sign your ledger when the work is done, as before. If you had
          already finished and signed, end your turn now.
        PROMPT
      end

      # The error the CLI reported, or failing that its last plain lines,
      # which is where a CLI that died on stderr left the reason.
      #
      # @param transcript [#error, #plain]
      # @return [String]
      def last_words(transcript)
        error = transcript.error.to_s.strip
        error.empty? ? transcript.plain.last(LAST_WORDS).join("\n").strip : error
      end
    end
  end
end
