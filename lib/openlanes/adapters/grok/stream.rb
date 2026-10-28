# frozen_string_literal: true

module OpenLanes
  module Adapters
    class Grok < Base
      # What `grok --output-format streaming-json` prints, put in the shapes
      # {Adapters::Stream} reads, so the meter, the tool count and the journal
      # stay in one place.
      #
      # Grok's dialect is the one {Adapters::Stream} would misread by shape:
      # an answer arrives as `text` events whose words sit under `data`; a
      # tool call is followed by `tool_call_update` events that also mention a
      # call; `usage` leaves cached input out of `input_tokens`; and `end`
      # repeats the run's totals, which counted again would double the meter.
      class Stream < Adapters::Stream
        # @param trace [String, nil]
        # @param session [String, nil] the id the session was started or
        #   resumed under, known before grok says it
        # @yieldparam progress [OpenLanes::Execution::Transcript::Progress]
        def initialize(trace: nil, session: nil, &)
          super(trace:, &)
          @session = session
          @said = +""
          @compacted = nil
        end

        # @return [String, nil]
        attr_reader :session

        # @return [Hash, nil] set once `/compact` reports it compacted; grok
        #   gives no sizes
        attr_reader :compacted

        # @return [OpenLanes::Execution::Transcript::Progress]
        def progress = super.with(session:)

        private

        # @param event [Hash]
        # @return [void]
        def handle(event)
          translated(event).each { super(it) }
        end

        # @param event [Hash] one grok event
        # @return [Array<Hash>] what {Adapters::Stream} should read instead
        def translated(event)
          case event["type"]
          when "text" then [said(event["data"].to_s)]
          when "tool_call" then [*closed, { "type" => "tool_call" }]
          when "usage" then [{ "type" => "usage", "usage" => metered(event["usage"] || {}) }]
          when "error" then [*closed, event]
          when "end" then ended(event)
          when "auto_compact_completed" then compacted!
          else []
          end
        end

        # The message so far, as a partial event, so finished journal lines
        # are taken as they arrive.
        #
        # @param data [String] the newest piece
        # @return [Hash]
        def said(data)
          @said << data
          { "type" => "message_delta", "text" => @said.dup }
        end

        # The message being written, closed: a tool call or the end of the
        # run is the only sign grok gives that it is finished.
        #
        # @return [Array<Hash>] empty when nothing is being written
        def closed
          return [] if @said.empty?

          message = { "type" => "message", "text" => @said }
          @said = +""
          [message]
        end

        # The session id grok confirms, and no usage: its totals repeat what
        # the `usage` events already counted.
        #
        # @param event [Hash]
        # @return [Array<Hash>]
        def ended(event)
          @session ||= event["sessionId"]
          [*closed, { "type" => "end" }]
        end

        # @return [Array<Hash>]
        def compacted!
          @compacted = {}
          []
        end

        # Grok counts cache reads and writes apart from `input_tokens`; the
        # meter counts everything sent, cached input included.
        #
        # @param usage [Hash]
        # @return [Hash]
        def metered(usage)
          cached = usage["cache_read_input_tokens"].to_i
          { "input_tokens"        => usage["input_tokens"].to_i + cached + usage["cache_creation_input_tokens"].to_i,
            "output_tokens"       => usage["output_tokens"].to_i,
            "cached_input_tokens" => cached }
        end
      end
    end
  end
end
