# frozen_string_literal: true

module OpenLanes
  module Adapters
    class Gemini < Base
      # What `gemini -o stream-json` prints, put in the shapes
      # {Adapters::Stream} reads.
      #
      # Read by shape, gemini's dialect goes wrong three ways: every
      # assistant `message` is a fragment (`delta: true`) that would be taken
      # as a whole message, `tool_use` names no start or call and would not be
      # counted, and a warning-level `error` (a loop it stopped itself) would
      # fail a run that ended normally. Usage arrives once, in `result.stats`,
      # with `input_tokens` already counting the cached part.
      class Stream < Adapters::Stream
        # @param trace [String, nil]
        # @yieldparam progress [OpenLanes::Execution::Transcript::Progress]
        def initialize(trace: nil, &)
          super
          @session = nil
          @said = +""
        end

        # @return [String, nil] the id `init` names
        attr_reader :session

        # @return [OpenLanes::Execution::Transcript::Progress]
        def progress = super.with(session:)

        private

        # @param event [Hash]
        # @return [void]
        def handle(event)
          translated(event).each { super(it) }
        end

        # @param event [Hash] one gemini event
        # @return [Array<Hash>] what {Adapters::Stream} should read instead
        def translated(event)
          case event["type"]
          when "init" then started(event)
          when "message" then event["role"] == "assistant" ? [said(event["content"].to_s)] : []
          when "tool_use" then [*closed, { "type" => "tool_call" }]
          when "error" then event["severity"] == "error" ? [*closed, { "type" => "error", "message" => event["message"] }] : []
          when "result" then [*closed, ended(event)]
          else []
          end
        end

        # @param event [Hash]
        # @return [Array<Hash>]
        def started(event)
          @session ||= event["session_id"]
          [{ "type" => "init" }]
        end

        # @param data [String] the newest fragment
        # @return [Hash] the message so far
        def said(data)
          @said << data
          { "type" => "message_delta", "text" => @said.dup }
        end

        # The message being written, closed by the next tool call or the end.
        #
        # @return [Array<Hash>]
        def closed
          return [] if @said.empty?

          message = { "type" => "message", "text" => @said }
          @said = +""
          [message]
        end

        # The run's usage, and its error when it ended in one.
        #
        # @param event [Hash]
        # @return [Hash]
        def ended(event)
          stats = event["stats"] || {}
          usage = { "input_tokens"        => stats["input_tokens"].to_i,
                    "output_tokens"       => stats["output_tokens"].to_i,
                    "cached_input_tokens" => stats["cached"].to_i }
          return { "type" => "end", "usage" => usage } unless event["status"] == "error"

          { "type" => "error", "message" => event.dig("error", "message") || "gemini reported an error", "usage" => usage }
        end
      end
    end
  end
end
