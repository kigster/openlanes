# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Events
    # One durable fact about a run: who did what to which plan, and when.
    #
    # Redaction is by construction, not by filter. Every kind declares the
    # payload keys it may carry, and building an event with any other key
    # raises, so no prompt, transcript or answer text can reach the log by
    # somebody adding `message:` to an emit. The only string in any payload
    # that is not an id is `failure`'s `error_class`, and it is cut to
    # {ERROR_CLASS_LIMIT} characters.
    #
    # @!attribute [r] event_id
    #   @return [String] SHA-256 hex from {Identity.event_id}; the dedupe key
    # @!attribute [r] kind
    #   @return [String] one of {KINDS}
    # @!attribute [r] at
    #   @return [String] ISO 8601 UTC
    # @!attribute [r] project
    #   @return [String, nil]
    # @!attribute [r] plan
    #   @return [String, nil] `NNN.MM`; nil for run-level events
    # @!attribute [r] run
    #   @return [String, nil] the run id {Runner} mints
    # @!attribute [r] agent
    #   @return [String, nil]
    # @!attribute [r] adapter
    #   @return [String, nil]
    # @!attribute [r] model
    #   @return [String, nil]
    # @!attribute [r] payload
    #   @return [Hash{String => Object}] only the keys {PAYLOAD_KEYS} allows
    Event = Data.define(:event_id, :kind, :at, :project, :plan, :run, :agent, :adapter, :model, :payload) do
      def initialize(event_id:, kind:, at:, project: nil, plan: nil, run: nil, agent: nil, adapter: nil, model: nil,
        payload: {})
        kind = kind.to_s
        raise ArgumentError, "unknown event kind #{kind.inspect}; known: #{Event::KINDS.join(", ")}" unless Event::KINDS.include?(kind)

        payload = Event.allowed!(kind, payload)
        at = at.is_a?(Time) ? at.utc.iso8601(3) : at.to_s
        super
      end

      # @return [Hash{String => Object}] what one JSONL line holds
      def to_h = super.transform_keys(&:to_s)

      # @return [String] one line, no newline
      def to_json(*) = JSON.generate(to_h)
    end

    class Event
      # Every kind the log records.
      KINDS = %w[run_started run_finished agent_started agent_finished block_raised human_answered
                 pr_opened pr_reviewed pr_merged pr_closed failure].freeze

      # The usage keys an `agent_finished` carries, from {Usage#to_h}.
      USAGE_KEYS = %w[input_tokens output_tokens cache_read_tokens cache_write_tokens cost_usd estimated
                      incomplete].freeze

      # The payload keys each kind may carry, and nothing else.
      PAYLOAD_KEYS = {
        "run_started"    => %w[jobs isolation],
        "run_finished"   => %w[rounds changed],
        "agent_started"  => %w[round invocation_start],
        "agent_finished" => %w[round invocation_start status duration_s] + USAGE_KEYS,
        "block_raised"   => %w[round invocation_start blocks],
        "human_answered" => %w[round block answered_at],
        "pr_opened"      => %w[number],
        "pr_reviewed"    => %w[number verdict],
        "pr_merged"      => %w[number],
        "pr_closed"      => %w[number],
        "failure"        => %w[round invocation_start error_class]
      }.freeze

      # The one free string the log keeps is a class name, and a class name
      # longer than this is not one.
      ERROR_CLASS_LIMIT = 120

      class << self
        # @param kind [String]
        # @param payload [Hash]
        # @return [Hash{String => Object}] frozen, string keys
        # @raise [ArgumentError] on any key outside the kind's allowlist
        def allowed!(kind, payload)
          clean = payload.to_h.transform_keys(&:to_s)
          stray = clean.keys - PAYLOAD_KEYS.fetch(kind)
          raise ArgumentError, "#{kind} may not carry #{stray.join(", ")}" unless stray.empty?

          clean["error_class"] = clean["error_class"].to_s[0, ERROR_CLASS_LIMIT] if clean.key?("error_class")
          clean.freeze
        end

        # @param hash [Hash] one parsed JSONL line
        # @return [OpenLanes::Events::Event]
        # @raise [ArgumentError, KeyError] when the line is not an event
        def from_h(hash)
          data = hash.transform_keys(&:to_s)
          new(**members.to_h { [it, it == :payload ? data.fetch("payload", {}) : data[it.to_s]] }, event_id: data.fetch("event_id"), kind: data.fetch("kind"), at: data.fetch("at"))
        end
      end
    end
  end
end
