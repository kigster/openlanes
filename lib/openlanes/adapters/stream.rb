# frozen_string_literal: true

require "json"

module OpenLanes
  module Adapters
    # A transcript for a CLI that prints JSON lines in a schema this harness
    # was not written against: `codex exec --json`, `pi --mode json`.
    #
    # It answers everything {OpenLanes::Execution::Transcript} answers, but
    # it reads events by shape rather than by name. Any `usage` object with
    # `input_tokens` and `output_tokens` moves the meter; any event whose
    # type mentions a tool, a command or an exec counts as a tool call; any
    # event typed as an error or a failure is the error. A CLI that renames
    # its events keeps working, and one that stops reporting usage shows a
    # meter at zero rather than a crash.
    class Stream
      # @param trace [String, nil] where every line is kept verbatim
      # @yieldparam progress [OpenLanes::Execution::Transcript::Progress]
      def initialize(trace: nil, &on_progress)
        @on_progress = on_progress
        @buffer = +""
        @plain = []
        @trace_path = trace
        @trace = trace && File.open(trace, "a")
        @up = 0
        @down = 0
        @cached = 0
        @tools = 0
        @activity = nil
        @result = nil
        @error = nil
      end

      # @return [Integer] tokens sent, cached input included
      attr_reader :up

      # @return [Integer] tokens generated
      attr_reader :down

      # @return [Integer] of {#up}, input the CLI reports as served from cache
      attr_reader :cached

      # @return [Integer]
      attr_reader :tools

      # @return [String, nil]
      attr_reader :activity

      # @return [String, nil] the last thing the agent said
      attr_reader :result

      # @return [Array<String>] lines that were not JSON
      attr_reader :plain

      # @return [String, nil]
      attr_reader :error

      # @return [String, nil]
      attr_reader :trace_path

      # @return [Integer, nil]
      attr_accessor :pid

      # These CLIs do not report sub-agents.
      #
      # @return [Integer]
      def spawned = 0

      # @return [Integer]
      def delegated = 0

      # @return [String, nil] nothing is sent through a side channel
      def message = nil

      # @return [Integer] new input plus output
      def fresh = up - cached + down

      # @return [Boolean]
      def failed? = !@error.nil?

      # @return [OpenLanes::Execution::Transcript::Progress]
      def progress = Execution::Transcript::Progress.new(activity:, up:, down:, subagents: 0, pid:, message: nil)

      # @param chunk [String, nil]
      # @return [void]
      def push(chunk)
        return if chunk.nil?

        @buffer << chunk
        while (index = @buffer.index("\n"))
          consume(@buffer.slice!(0..index).chomp)
        end
      end

      # @return [void]
      def finish
        consume(@buffer.slice!(0..-1).to_s)
        @trace&.close
        @trace = nil
      end

      private

      # @param line [String]
      # @return [void]
      def consume(line)
        text = line.strip
        return if text.empty?

        @trace&.write("#{text}\n")
        @trace&.flush
        event = text.start_with?("{") ? parse(text) : nil
        return @plain << text if event.nil?

        handle(event)
      end

      # @param text [String]
      # @return [Hash, nil]
      def parse(text)
        value = JSON.parse(text)
        value.is_a?(Hash) ? value : nil
      rescue JSON::ParserError
        nil
      end

      # @param event [Hash]
      # @return [void]
      def handle(event)
        type = event["type"].to_s
        meter(event)
        @tools += 1 if type.match?(/tool|command|exec/i) && type.match?(/start|call|begin/i)
        @error = describe_error(event) if type.match?(/error|fail/i)
        said = text_in(event)
        if said
          @activity = said.lines.first.to_s.strip[0, Execution::Transcript::LIMIT]
          @result = said
        end
        @on_progress&.call(progress)
      end

      # Usage counts arrive per turn, so they are added rather than replaced.
      #
      # @param event [Hash]
      # @return [void]
      def meter(event)
        usage = find(event, "usage")
        return unless usage.is_a?(Hash)

        @up += usage["input_tokens"].to_i
        @down += usage["output_tokens"].to_i
        @cached += usage["cached_input_tokens"].to_i
      end

      # @param event [Hash]
      # @return [String]
      def describe_error(event)
        (find(event, "message") || find(event, "error") || event["type"]).to_s
      end

      # The agent's own words, wherever this CLI put them.
      #
      # @param event [Hash]
      # @return [String, nil]
      def text_in(event)
        text = find(event, "text")
        text.is_a?(String) && !text.strip.empty? ? text : nil
      end

      # Depth-first search for the first value under +key+.
      #
      # @param node [Object]
      # @param key [String]
      # @return [Object, nil]
      def find(node, key)
        case node
        when Hash
          return node[key] if node.key?(key)

          node.each_value do |value|
            found = find(value, key)
            return found unless found.nil?
          end
          nil
        when Array
          node.each do |value|
            found = find(value, key)
            return found unless found.nil?
          end
          nil
        end
      end
    end
  end
end
