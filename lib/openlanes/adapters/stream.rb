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
      # Events that carry part of a message still being written. Only its
      # finished lines are read out of one, and the closing message does not
      # read them again (see {#take_partial}).
      PARTIAL = /delta|update|partial|chunk/i

      # Events that repeat messages already closed: pi's `turn_end` and
      # `agent_end`, or anything carrying a `messages` list.
      SUMMARY = /turn|agent|session|run/i

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
        @journal = []
        @heard = {}
        @closed = Hash.new(0)
        @open = { text: +"", taken: 0 }
        @pending = Hash.new(0)
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

      # @return [Array<OpenLanes::Plans::Journal::Entry, OpenLanes::Plans::Journal::Rejection>]
      #   the journal lines printed so far
      def journal = @journal.dup

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

      # No sub-agents, running or spawned: codex and pi never say they delegated.
      #
      # @return [OpenLanes::Execution::Transcript::Progress]
      def progress
        Execution::Transcript::Progress.new(activity:,
          up:,
          down:,
          subagents: 0,
          pid:,
          message: nil,
          running: [],
          journal: @journal.dup.freeze)
      end

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
        unless type.match?(/tool|command|exec/i)
          if type.match?(PARTIAL)
            take_partial(event)
          else
            take_journal(event, summary: type.match?(SUMMARY) || event.key?("messages"))
          end
        end
        @on_progress&.call(progress)
      end

      # Journal lines (M2) in what the agent itself said, in every text block
      # of every message it finished. Not {#text_in}, which takes the first
      # `text` anywhere in the event: that can be a tool's output, which would
      # make a file the agent read into its memory, and it misses a line in a
      # message's second block.
      #
      # A CLI read by shape delivers the same message more than once: as it
      # closes, and again in a summary of the turn or the run. A message with
      # an id is taken once by its id. One without is always taken as it
      # closes, since an agent may mean `todo U1` again after it said `done
      # U1`; a summary skips as many copies of its words as have closed, and
      # takes the rest.
      #
      # @param event [Hash]
      # @param summary [Boolean] whether the event repeats closed messages
      # @return [void]
      def take_journal(event, summary:)
        seen = Hash.new(0)
        messages_in(event).each do |message|
          texts = texts_of(message)
          next if texts.empty?

          if (id = message["id"])
            next if @heard.key?(id)

            @heard[id] = true
          else
            next if summary && (seen[texts] += 1) <= @closed[texts]

            @closed[texts] += 1
          end
          texts.flat_map { Plans::Journal.scan(it) }.each { keep(it) }
          @open = { text: +"", taken: 0 }
        end
      end

      # The finished lines of a message still being written, as they arrive,
      # so an agent killed before the message closes keeps what it printed.
      # An event carries either the message so far (pi's `message`, codex's
      # `item`) or only the newest piece of it (a `delta`).
      #
      # @param event [Hash]
      # @return [void]
      def take_partial(event)
        whole = messages_in(event).map { texts_of(it).join("\n") }.reject(&:empty?).last
        whole ? @open[:text] = +whole : @open[:text] << delta_in(event).to_s
        cut = @open[:text].rindex("\n") or return

        entries = Plans::Journal.scan(@open[:text][0..cut])
        entries.drop(@open[:taken]).each do |entry|
          @journal << entry
          @pending[entry] += 1
        end
        @open[:taken] = entries.size
      end

      # An entry from a closing message, unless it was already taken from that
      # message while it was being written.
      #
      # @param entry [OpenLanes::Plans::Journal::Entry, OpenLanes::Plans::Journal::Rejection]
      # @return [void]
      def keep(entry)
        return @pending[entry] -= 1 if @pending[entry].positive?

        @journal << entry
      end

      # @param event [Hash]
      # @return [String, nil] the newest piece of text a partial event carries
      def delta_in(event)
        [event["delta"], event.dig("assistantMessageEvent", "delta")].each do |delta|
          return delta if delta.is_a?(String)
          return delta["text"] if delta.is_a?(Hash) && delta["text"].is_a?(String)
        end
        nil
      end

      # The agent's own messages an event carries: one under `item` (codex)
      # or `message` (pi), a list under `messages`, or the event itself when
      # it is a message with its words at the top level. A message that names
      # a role other than the assistant's is a prompt or a tool result, and
      # an item typed as anything but a message is a command, a file change
      # or reasoning.
      #
      # @param event [Hash]
      # @return [Array<Hash>]
      def messages_in(event)
        itself = event.key?("content") || event["text"].is_a?(String) ? event : nil
        found = [event["item"], event["message"], *Array(event["messages"]), itself]
        found.select do |message|
          message.is_a?(Hash) &&
            [nil, "assistant"].include?(message["role"]) &&
            (message["type"].nil? || message["type"].to_s.match?(/message|assistant/i))
        end
      end

      # @param message [Hash]
      # @return [Array<String>] its text, block by block, tool calls left out
      def texts_of(message)
        content = message["content"]
        blocks = if content.is_a?(Array)
                   content.select { it.is_a?(Hash) && [nil, "text", "output_text"].include?(it["type"]) }.map { it["text"] }
                 else
                   [message["text"], content]
                 end
        blocks.select { it.is_a?(String) && !it.strip.empty? }
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
