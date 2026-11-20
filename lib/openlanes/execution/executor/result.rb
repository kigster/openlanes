# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What a {Result} that says nothing of them was: not killed, no
      # process, nothing cached, not throttled, no tool call, no lesson
      # offered and none cited.
      RESULT_DEFAULTS = { killed: nil, pid: nil, cached: 0, throttled: false, tools: 0, offered: [].freeze,
                          cited: [].freeze }.freeze

      # What one invocation did, and what it spent doing it.
      #
      # {#to_ary} is deliberate: every caller of {Executor#call} destructures
      # `ok, note = executor.call(...)`, and the meter is an addition to that
      # answer rather than a replacement for it. Callers that want the tokens
      # ask for them by name.
      #
      # @!attribute [r] ok
      #   @return [Boolean]
      # @!attribute [r] note
      #   @return [String] one line, for the report
      # @!attribute [r] up
      #   @return [Integer] tokens sent, sub-agents included
      # @!attribute [r] down
      #   @return [Integer] tokens generated
      # @!attribute [r] subagents
      #   @return [Integer] sub-agents this agent spawned
      # @!attribute [r] delegated
      #   @return [Integer] of {#up}, how much arrived as an unsplit sub-agent
      #     total rather than as a direction of its own
      # @!attribute [r] seconds
      #   @return [Float] wall clock, from argv to exit
      # @!attribute [r] killed
      #   @return [Symbol, nil] :timeout when the clock's backstop fired, :key
      #     when somebody pressed k, :budget when the token meter crossed the
      #     cap, :quit when the grace period after q ran out, nil otherwise
      # @!attribute [r] pid
      #   @return [Integer, nil]
      # @!attribute [r] cached
      #   @return [Integer] of {#up}, read back from the prompt cache
      # @!attribute [r] throttled
      #   @return [Boolean] whether it failed on the provider's rate limit or
      #     overload, having waited as long as {Throttle::Backoff} allows,
      #     rather than at anything the agent did
      # @!attribute [r] tools
      #   @return [Integer] tool calls the agent made
      # @!attribute [r] offered
      #   @return [Array<String>] the lesson ids its prompt carried (decision C5)
      # @!attribute [r] cited
      #   @return [Array<String>] of {#offered}, the ids its final report named
      # @return [Data]
      Result = Data.define(:ok,
        :note,
        :up,
        :down,
        :subagents,
        :delegated,
        :seconds,
        :killed,
        :pid,
        :cached,
        :throttled,
        :tools,
        :offered,
        :cited) do
        def initialize(**fields) = super(**RESULT_DEFAULTS, **fields)

        # @return [Integer] new input, cache writes and output
        def fresh = up - cached + down

        # Whether it failed before spending anything: no tokens in, none out,
        # no tool call, and nobody killed it. The same test {#lost_session}
        # makes of a transcript, so a start that cost nothing costs the agent
        # no round either (plan 065.00).
        #
        # @return [Boolean]
        def failed_start? = !ok && killed.nil? && !throttled && Executor.spent_nothing?(self)

        # Whether that failed start was the CLI refusing to authenticate, read
        # from its own words. The engine pauses the CLI rather than starting
        # the next agent on it into the same wall.
        #
        # @return [Boolean]
        def auth_failure? = failed_start? && AUTH_FAILURE.match?(note.to_s)

        # The CLI's own words for the authentication failure, without the
        # exit code and trace path the note carries, so the idle line reads
        # `claude paused: OAuth session expired`.
        #
        # @return [String, nil] nil when it was not one
        def auth_reason = (note.to_s[AUTH_FAILURE] if auth_failure?)

        # @return [Array(Boolean, String)]
        def to_ary = [ok, note]
      end
    end
  end
end
