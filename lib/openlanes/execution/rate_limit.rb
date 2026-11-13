# frozen_string_literal: true

module OpenLanes
  module Execution
    # A provider that turned an invocation away for load rather than for
    # anything the agent did: HTTP 429, `rate_limit_error`, `overloaded_error`
    # or 529, in whatever words the adapter's CLI printed them. With seven
    # jobs at once, one burst used to cost every plan an attempt; such a run
    # is waited out and started again instead, and costs none.
    #
    # {Executor#lost_session} already retries a resumed session that failed
    # before spending anything, which covers an overload at start-up. This
    # covers the rest: a failure at any point whose own words say "rate limit".
    #
    # @!attribute [r] kind
    #   @return [Symbol] `:rate_limited` or `:overloaded`
    # @!attribute [r] retry_after
    #   @return [Integer, nil] seconds the provider asked for, when it said
    # @!attribute [r] line
    #   @return [String] what the CLI printed, cut to one line
    RateLimit = Data.define(:kind, :retry_after, :line) do
      # @param attempt [Integer] how many times this plan has been turned away
      #   in a row, from 1
      # @param rng [#rand] for the jitter
      # @return [Float] seconds to wait: what the provider asked for, else
      #   {RateLimit::BASE} doubled per attempt, capped at {RateLimit::CAP},
      #   plus up to a quarter more, so the jobs do not all return at once
      def delay(attempt, rng: Random)
        return retry_after.to_f if retry_after

        wait = [RateLimit::BASE * (2**(attempt.clamp(1, 32) - 1)), RateLimit::CAP].min
        wait + (wait * RateLimit::JITTER * rng.rand)
      end

      # @param seconds [Numeric]
      # @return [String] what the board shows
      def phrase(seconds) = "rate-limited, retry in #{seconds.round}s"
    end

    class RateLimit
      # Seconds before the first retry.
      BASE = 30.0

      # The longest wait between two retries.
      CAP = 900.0

      # The share of a wait added at random.
      JITTER = 0.25

      # The provider is out of capacity for everyone.
      OVERLOADED = /overloaded_error|\b529\b|\boverloaded\b/i

      # This account asked for more than it may.
      LIMITED = /rate_limit_error|\b429\b|rate[ _-]?limit(?:ed)?\b|too many requests/i

      # `retry-after: 20`, `"retry_after": 20`, `retry after 20s`.
      RETRY_AFTER = /retry[ _-]after\W{0,4}(\d+)/i

      class << self
        # @param status [Process::Status, nil] how the CLI exited
        # @param transcript [#error, #plain] what it printed
        # @return [OpenLanes::Execution::RateLimit, nil] nil for a run that
        #   succeeded or failed for any other reason
        def detect(status, transcript)
          return nil if status&.success? && !transcript.failed?

          said = [transcript.error, *transcript.plain].map(&:to_s).reject(&:empty?)
          hit = said.rfind { OVERLOADED.match?(it) || LIMITED.match?(it) }
          hit && from(hit, said)
        end

        private

        # @param hit [String] the line that names the limit
        # @param said [Array<String>] everything the CLI printed
        # @return [OpenLanes::Execution::RateLimit]
        def from(hit, said)
          new(kind: OVERLOADED.match?(hit) ? :overloaded : :rate_limited,
            retry_after: said.join("\n")[RETRY_AFTER, 1]&.to_i,
            line: hit.lines.first.to_s.strip[0, 200])
        end
      end
    end
  end
end
