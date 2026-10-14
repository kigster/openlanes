# frozen_string_literal: true

require "time"

module OpenLanes
  module Apps
    # Where one process of a running app stands, and the `<app>` object of
    # the `apps` and `app` events the control room reads (plan 012, B1).
    # The Preview tab draws only what arrives in this shape, so every field
    # is said here once and {#to_h} is the wire.
    #
    # @!attribute [r] plan
    #   @return [String] the ordinal, `012.00`
    # @!attribute [r] branch
    #   @return [String] the checkout's branch
    # @!attribute [r] process
    #   @return [String] the process's name
    # @!attribute [r] state
    #   @return [String] one of {STATES}
    # @!attribute [r] port
    #   @return [Integer] the port it was given
    # @!attribute [r] preview
    #   @return [Boolean] the process the tab shows
    # @!attribute [r] url
    #   @return [String] `http://127.0.0.1:<port><ready path or />`
    # @!attribute [r] framing
    #   @return [String, nil] `frame` or `window` once the preview process is
    #     ready; nil before that and on every other process
    # @!attribute [r] reason
    #   @return [String, nil] why it failed, for a person
    # @!attribute [r] at
    #   @return [Time] when it entered this state
    Status = Data.define(:plan, :branch, :process, :state, :port, :preview, :url, :framing, :reason, :at) do
      def initialize(plan:, branch:, process:, state:, port:, preview: false, url: nil, framing: nil, reason: nil, at: Time.now)
        raise ArgumentError, "state #{state.inspect} is not one of #{Status::STATES.join(", ")}" unless Status::STATES.include?(state.to_s)

        super(plan:, branch:, process:, state: state.to_s, port:, preview:, url: url || "http://#{Status::HOST}:#{port}/",
          framing: framing&.to_s, reason:, at:)
      end

      # @return [Boolean]
      def ready? = state == "ready"

      # @return [Boolean]
      def failed? = state == "failed"

      # @return [Hash] the wire's `<app>`, string keys
      def to_h
        { "plan" => plan, "branch" => branch, "process" => process, "state" => state, "port" => port,
          "preview" => preview, "url" => url, "framing" => framing, "reason" => reason, "at" => at.utc.iso8601 }
      end
    end

    class Status
      # Every state a process passes through.
      STATES = %w[starting ready restarting stopped failed].freeze

      # Where every app listens: nothing here is reachable from another machine.
      HOST = "127.0.0.1"
    end
  end
end
