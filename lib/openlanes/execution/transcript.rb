# frozen_string_literal: true

require "json"

module OpenLanes
  module Execution
    # What an agent is doing, while it is still doing it.
    #
    # `claude -p` prints nothing until it exits, so a fifteen-minute agent used to
    # sit behind a spinner that said only its name. Asked for `--output-format
    # stream-json` it emits one JSON object per line as it works, and this turns
    # that stream into the short phrase a spinner line has room for: "editing
    # spec.md", "reading plan.md", whatever the agent last said about itself.
    #
    # Three things make this less trivial than parsing JSON.
    #
    # Chunks arrive from `readpartial`, so a line is split across two of them as
    # often as not. {#push} buffers and only ever parses whole lines.
    #
    # Not every line is JSON. `claude` reports its own failures as prose on
    # stdout, and the 401 that cost a whole run three minutes an agent was one of
    # those. Those lines are kept in {#plain} so a failure can still be explained
    # by what was actually printed.
    #
    # The reader runs on its own thread, so {#activity} is written from one
    # thread and read from another. It is a single assignment of an immutable
    # string, which is why there is no lock here.
    #
    # Every line is also kept verbatim in an optional trace file, written before
    # anything is made of it, so a run that failed can be read back afterwards
    # even where this parser made nothing of an event it had never seen. See
    # {Executor::TRACE_DIR} for where those land and how to read one.
    class Transcript
      # What one line of the display knows: the phrase, and the meter beside it.
      #
      # Yielded whole rather than as loose arguments so a caller cannot render
      # half an update, and frozen so the reader thread and the drawing thread
      # are never looking at the same mutable object.
      #
      # @!attribute [r] activity
      #   @return [String, nil] the last thing the agent was seen doing
      # @!attribute [r] up
      #   @return [Integer] tokens sent, cache reads included
      # @!attribute [r] down
      #   @return [Integer] tokens generated
      # @!attribute [r] subagents
      #   @return [Integer] sub-agents spawned so far
      # @!attribute [r] pid
      #   @return [Integer, nil] the `claude` process, once the harness has
      #     found it — nil until then, and for callers that never look
      # @!attribute [r] message
      #   @return [String, nil] the last thing the agent chose to say directly,
      #     via `SendUserMessage`, or nil if it never sent one
      # @!attribute [r] context
      #   @return [Integer, nil] tokens in the agent's context as of its latest
      #     message, nil until one has closed, and for streams that never say
      # @!attribute [r] session
      #   @return [String, nil] the CLI's session id, from its `init` event,
      #     which is what `--resume` carries the agent on in (W28)
      # @!attribute [r] running
      #   @return [Array<String>] the sub-agents working right now, by name,
      #     oldest first; empty for a stream that never says (codex, pi)
      # @!attribute [r] journal
      #   @return [Array<OpenLanes::Plans::Journal::Entry, OpenLanes::Plans::Journal::Rejection>]
      #     every journal line (M2) the agent has printed so far, in order. The
      #     whole list rather than the latest, because a snapshot can be
      #     skipped by a reader that is busy, and an entry must not be: the
      #     dispatcher keeps its place in the list and writes what is past it.
      Progress = Data.define(:activity,
        :up,
        :down,
        :subagents,
        :pid,
        :message,
        :context,
        :session,
        :running,
        :journal) do
        def initialize(pid: nil, message: nil, context: nil, session: nil, running: [], journal: [], **rest) = super
      end

      # The tools that start a sub-agent. `claude` called it `Task` and renamed
      # it `Agent`; a transcript that knew only one name would show a run on the
      # other CLI version with no sub-agents at all.
      DELEGATES = %w[Task Agent].freeze

      # The one kind of line the trace does not keep.
      #
      # `--include-partial-messages` is what makes {#meter} possible, and it
      # also emits one event per handful of generated characters. Those are the
      # bulk of the stream and the only part of it nothing reads back: a
      # fifteen-minute agent writes thousands of them, and they would bury the
      # events a failed run is actually read for. Matched as a substring rather
      # than parsed because the trace is written before a line is understood,
      # which is what makes it complete when the process dies mid-invocation.
      DELTA_NOISE = '"content_block_delta"'

      # Longest phrase kept. A sanity cap, not a layout rule: each place that
      # draws a phrase cuts it to the room it has.
      LIMIT = 300

      # How each tool reads as something being done, rather than as a tool name.
      # A spinner says what is happening; "Edit" is a noun and says nothing.
      VERBS = {
        "Read" => "reading", "Write" => "writing", "Edit" => "editing",
        "MultiEdit" => "editing", "NotebookEdit" => "editing",
        "Bash" => "running", "Grep" => "searching for", "Glob" => "looking for",
        "Task" => "delegating", "Agent" => "delegating", "TodoWrite" => "planning",
        "WebFetch" => "fetching", "WebSearch" => "searching the web for",
        "SendUserMessage" => "saying"
      }.freeze

      # The input key worth naming, per tool, in the order we would rather say it.
      # `description` outranks `command` deliberately: Claude's Bash tool carries
      # a written summary of why it is running something, and "Read NOTES.md" is
      # a better spinner line than sixty characters of absolute path.
      SUBJECTS = %w[file_path pattern description command query url].freeze

      # @param trace [String, nil] a file to keep the raw stream in, or nil to
      #   keep none. Every line is written before anything is made of it, so a
      #   run that failed can be read back afterwards even where this parser made
      #   nothing of an event it had never seen.
      # @yieldparam progress [OpenLanes::Execution::Transcript::Progress] each time the
      #   agent moves on to something new, and each time the meter moves
      def initialize(trace: nil, &on_progress)
        @on_progress = on_progress
        @buffer = +""
        @plain = []
        @activity = nil
        @message = nil
        @result = nil
        @error = nil
        @trace_path = trace
        @trace = trace && File.open(trace, "a")
        @tools = 0
        @main = { up: 0, down: 0, cached: 0 }
        @streamed = {}
        @tasks = {}
        @spawned = 0
        @running = {}
        @context = nil
        @session = nil
        @compacted = nil
        @journal = []
      end

      # Everything sent to the model, which on any turn after the first is
      # mostly cache reads: a typical agent turn is two fresh input tokens
      # against a quarter of a million read back from cache. Counting only the
      # fresh ones would report a fifteen-minute agent as having said nothing.
      #
      # @return [Integer]
      def up = @main[:up] + streamed[:up] + delegated

      # @return [Integer] tokens the model generated, thinking included
      def down = @main[:down] + streamed[:down]

      # Of {#up}, what was read back from the prompt cache: the context every
      # turn re-sends. A budget that counts it ends a 30k-context agent after
      # ten turns, whatever it was doing, so {#fresh} leaves it out.
      #
      # @return [Integer]
      def cached = @main[:cached] + streamed[:cached]

      # What this invocation added: new input, cache writes and output.
      #
      # @return [Integer]
      def fresh = up - cached + down

      # @return [Integer] sub-agents this invocation started
      attr_reader :spawned

      # The `claude` process this transcript is reading, set by the {Executor}
      # once it has found the child, so the spinner line can name a pid someone
      # can actually `ps` while the agent runs.
      #
      # @return [Integer, nil]
      attr_accessor :pid

      # Sub-agent totals arrive as one number with no split between what went up
      # and what came back, so they are counted as {#up}. They are held here as
      # well, unmixed, because a report that says "of which N could not be
      # split" is honest and one that quietly rounds is not.
      #
      # @return [Integer]
      def delegated
        @tasks.reject { |_, task| @streamed.key?(task[:tool_use_id]) }
              .sum { |_, task| task[:total] }
      end

      # @return [OpenLanes::Execution::Transcript::Progress] a snapshot, safe to keep
      def progress
        Progress.new(activity: @activity,
          up:,
          down:,
          subagents: @spawned,
          pid: @pid,
          message: @message,
          context: @context,
          session: @session,
          running: @running.values,
          journal: @journal.dup.freeze)
      end

      # The sub-agents started and not yet answered, by name. A count would
      # have been enough for the meter; the page draws each one beside its
      # parent, so it needs to know which.
      #
      # @return [Array<String>] oldest first
      def running = @running.values

      # @return [String, nil] the session id from the stream's `init` event
      attr_reader :session

      # @return [Array<OpenLanes::Plans::Journal::Entry, OpenLanes::Plans::Journal::Rejection>]
      #   the journal lines printed so far
      def journal = @journal.dup

      # What a `/compact` reported in its `compact_boundary` event:
      # `pre_tokens`, `post_tokens` and the rest of its `compact_metadata`.
      #
      # @return [Hash, nil] nil until the session has been compacted
      attr_reader :compacted

      # What the agent's own context holds now: everything its latest message
      # was sent, fresh, cache writes and cache reads alike. Each turn re-sends
      # the whole conversation, so the last message's input is the context, and
      # adding them up across turns would count it once per turn. A sub-agent
      # has a context of its own and does not fill this one.
      #
      # @return [Integer, nil] nil until the first message has closed
      attr_reader :context

      # @return [Integer] how many tool calls have gone past, which is the one
      #   honest measure of how much work an agent that says "done" actually did
      attr_reader :tools

      # @return [String, nil] the file the raw stream is being kept in
      attr_reader :trace_path

      # @return [String, nil] the last thing the agent was seen doing
      attr_reader :activity

      # @return [String, nil] the last thing the agent sent via `SendUserMessage`
      attr_reader :message

      # @return [String, nil] the final text, from the `result` event
      attr_reader :result

      # @return [Array<String>] lines that were not JSON, in order
      attr_reader :plain

      # @return [Boolean] whether the stream reported its own failure
      def failed? = !@error.nil?

      # @return [String, nil] what the agent said went wrong
      attr_reader :error

      # Feed one chunk of stdout. Safe to call with a partial line, which is the
      # normal case.
      #
      # @param chunk [String, nil]
      # @return [void]
      def push(chunk)
        return if chunk.nil?

        @buffer << chunk
        while (index = @buffer.index("\n"))
          line = @buffer.slice!(0..index).chomp
          consume(line)
        end
      end

      # Whatever is left when the process exits, which may be a last line with no
      # newline after it.
      #
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

        record(text)

        unless text.start_with?("{")
          @plain << text
          return
        end

        event = begin
          JSON.parse(text)
        rescue JSON::ParserError
          @plain << text
          return
        end

        handle(event)
      end

      # Written before the line is understood, and flushed, so the file is a
      # complete record even when the process dies mid-invocation.
      #
      # @param text [String]
      # @return [void]
      def record(text)
        return unless @trace
        return if text.include?(DELTA_NOISE)

        @trace.write("#{text}\n")
        @trace.flush
      end

      # @param event [Hash]
      # @return [void]
      def handle(event)
        case event["type"]
        when "assistant"
          grew = capture_journal(event)
          capture_message(event)
          @tools += tool_calls(event)
          delegate(event)
          # A journal line is published even when the phrase is the one
          # already showing: the dispatcher keeps only the snapshots it is
          # handed, so one held back here is lost if the round is killed
          # before anything else publishes.
          published = announce(phrase_for(event))
          publish if grew && !published
        when "user" then collect(event)
        when "stream_event" then meter(event)
        when "system" then system_event(event)
        when "result" then record_result(event)
        end
      end

      # Journal lines (M2) in the agent's own text. A sub-agent's are left
      # out: it was not told the format, the journal is its parent's, and a
      # line it printed reaches the parent as a tool result the parent can
      # repeat if it matters. Text only, never a tool's input, so a file the
      # agent writes that happens to hold such a line is not a journal entry.
      #
      # @param event [Hash]
      # @return [Boolean] whether the journal grew
      def capture_journal(event)
        return false unless event["parent_tool_use_id"].nil?

        lines = blocks_of(event, "text").flat_map { Plans::Journal.scan(it["text"]) }
        @journal.concat(lines)
        !lines.empty?
      end

      # `--brief` gives the agent SendUserMessage, and what it sends is the
      # one line on the screen the agent itself chose. It outranks the tool
      # phrase until the agent sends another.
      #
      # @param event [Hash]
      # @return [void]
      def capture_message(event)
        blocks = event.dig("message", "content")
        return unless blocks.is_a?(Array)

        blocks.each do |block|
          next unless block.is_a?(Hash) && block["type"] == "tool_use" && block["name"] == "SendUserMessage"

          text = block.dig("input", "message").to_s.strip
          @message = clip(text) unless text.empty?
        end
      end

      # A sub-agent is running from the `Task` call that starts it until the
      # `tool_result` that answers that call. Its name is the `subagent_type`
      # the call asked for, which is what a person would recognise
      # ("leah-researcher"), and its `description` only when it named none.
      # A sub-agent's own calls carry a `parent_tool_use_id` and are read the
      # same way, so one it starts in turn is a sub-agent too.
      #
      # @param event [Hash]
      # @return [void]
      def delegate(event)
        started = blocks_of(event, "tool_use").select { DELEGATES.include?(it["name"]) && it["id"] }
        return if started.empty?

        started.each do |block|
          input = block["input"].is_a?(Hash) ? block["input"] : {}
          name = [input["subagent_type"], input["description"]].map { it.to_s.strip }.find { !it.empty? }
          @running[block["id"]] = name || "sub-agent"
        end
        publish
      end

      # The `tool_result` that answers a `Task` call is the sub-agent's
      # return, so it leaves the list there.
      #
      # @param event [Hash]
      # @return [void]
      def collect(event)
        done = blocks_of(event, "tool_result").filter_map { it["tool_use_id"] }.select { @running.key?(it) }
        return if done.empty?

        done.each { @running.delete(it) }
        publish
      end

      # @param event [Hash]
      # @param type [String]
      # @return [Array<Hash>] the message's content blocks of that type
      def blocks_of(event, type)
        blocks = event.dig("message", "content")
        return [] unless blocks.is_a?(Array)

        blocks.select { it.is_a?(Hash) && it["type"] == type }
      end

      # @param event [Hash]
      # @return [Integer] how many tools this one message called
      def tool_calls(event)
        blocks = event.dig("message", "content")
        return 0 unless blocks.is_a?(Array)

        blocks.count { |block| block.is_a?(Hash) && block["type"] == "tool_use" }
      end

      # Where the token count comes from.
      #
      # Only `message_delta` is trusted. The `assistant` events carry a usage
      # block too, and its input side is right, but its `output_tokens` is the
      # placeholder the API sends when a message *starts*: a four-thousand-token
      # answer reports 2 there. `message_delta` closes each message with the
      # settled figure for both directions, which is why {Executor} asks for
      # `--include-partial-messages` at all.
      #
      # A message from a sub-agent carries `parent_tool_use_id`, and is kept in
      # its own bucket so {#delegated} knows not to count that sub-agent twice.
      #
      # @param event [Hash]
      # @return [void]
      def meter(event)
        return unless event.dig("event", "type") == "message_delta"

        usage = event.dig("event", "usage") or return
        bucket = bucket_for(event["parent_tool_use_id"])
        sent = usage.values_at("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens").compact.sum
        bucket[:up] += sent
        @context = sent if event["parent_tool_use_id"].nil?
        bucket[:down] += usage["output_tokens"].to_i
        bucket[:cached] += usage["cache_read_input_tokens"].to_i
        publish
      end

      # @param parent [String, nil] the tool call a sub-agent's message belongs to
      # @return [Hash] the counters that message belongs in
      def bucket_for(parent)
        return @main if parent.nil?

        @streamed[parent] ||= { up: 0, down: 0, cached: 0 }
      end

      # @return [Hash] every streamed sub-agent's counters, added together
      def streamed
        @streamed.values.each_with_object({ up: 0, down: 0, cached: 0 }) do |b, sum|
          sum[:up] += b[:up]
          sum[:down] += b[:down]
          sum[:cached] += b[:cached]
        end
      end

      # The `system` events read: the session starting, the session compacted,
      # a sub-agent starting, and a sub-agent reporting what it spent.
      #
      # `claude` reports a sub-agent's spend as a single `total_tokens` with no
      # split, and reports it cumulatively: the last number for a task is the
      # whole of it, not an increment. So the total is stored per task and
      # replaced rather than added, which also makes a `task_progress` stream
      # and a closing `task_notification` for the same task agree instead of
      # counting it twice.
      #
      # @param event [Hash]
      # @return [void]
      def system_event(event)
        case event["subtype"]
        when "init" then begin_session(event)
        when "compact_boundary" then @compacted = event["compact_metadata"] || {}
        when "task_started" then start_task(event)
        when "task_progress", "task_notification" then update_task(event)
        end
      end

      # The first `init` names the session. A resumed one names the same id
      # again, so the first is kept rather than the last.
      #
      # @param event [Hash]
      # @return [void]
      def begin_session(event)
        @session ||= event["session_id"]
        publish
      end

      # @param event [Hash]
      # @return [void]
      def start_task(event)
        id = event["task_id"] or return

        @tasks[id] ||= { tool_use_id: event["tool_use_id"], total: 0 }
        @spawned = @tasks.size
        publish
      end

      # @param event [Hash]
      # @return [void]
      def update_task(event)
        id = event["task_id"] or return

        task = (@tasks[id] ||= { tool_use_id: event["tool_use_id"], total: 0 })
        task[:tool_use_id] ||= event["tool_use_id"]
        task[:total] = event.dig("usage", "total_tokens").to_i
        @spawned = @tasks.size
        publish
      end

      # The `result` event settles what the stream could only accumulate: its
      # usage is the invocation's own final accounting, so it replaces the
      # running total rather than adding to it. Sub-agent spend is left alone,
      # because `claude` leaves it out of this figure — a run whose two
      # sub-agents burned 34k each reported 493 output tokens here.
      #
      # @param event [Hash]
      # @return [void]
      def record_result(event)
        @result = event["result"].to_s
        @error = @result if event["is_error"]
        settle(event["usage"])
        @spawned = [@spawned, event.dig("subagent_stats", "spawned").to_i].max
        # The invocation is over, so whatever it started is over with it,
        # answered or not.
        @running.clear
        publish
      end

      # The most recent block wins: an agent that says "now I'll edit the spec"
      # and then edits it is more usefully reported as editing it.
      #
      # @param event [Hash]
      # @return [String, nil]
      def phrase_for(event)
        blocks = event.dig("message", "content")
        return nil unless blocks.is_a?(Array)

        blocks.reverse.filter_map { |block| block_phrase(block) }.first
      end

      # @param block [Hash]
      # @return [String, nil]
      def block_phrase(block)
        case block["type"]
        when "tool_use" then tool_phrase(block)
        when "text" then sentence(block["text"])
        end
      end

      # @param block [Hash]
      # @return [String]
      def tool_phrase(block)
        verb = VERBS.fetch(block["name"].to_s, "using #{block["name"]}")
        input = block["input"]
        return verb unless input.is_a?(Hash)

        key = SUBJECTS.find { |k| input[k].to_s.strip != "" }
        return verb unless key
        # A description is already a phrase. Prefixing it with a verb gives
        # "running Read NOTES.md", which reads worse than either half alone.
        return clip(noun(key, input[key])) if key == "description"

        clip("#{verb} #{noun(key, input[key])}")
      end

      # A path is only ever interesting by its last segment on a line this short.
      #
      # @param key [String]
      # @param value [Object]
      # @return [String]
      def noun(key, value)
        text = value.to_s.strip.tr("\n", " ").squeeze(" ")
        key == "file_path" ? File.basename(text) : text
      end

      # The agent's own narration, first sentence only. Everything after it is
      # detail the spinner has no room for.
      #
      # @param text [String, nil]
      # @return [String, nil]
      def sentence(text)
        line = text.to_s.split("\n").map(&:strip).find { |l| !l.empty? } or return nil
        line = line.sub(/\A[#>*\-\s]+/, "").split(/(?<=[.!?])\s/).first.to_s.strip
        line.empty? ? nil : clip(line)
      end

      # @param text [String]
      # @return [String]
      def clip(text) = text.length > LIMIT ? "#{text[0, LIMIT - 1]}…" : text

      # @param usage [Hash, nil] the `result` event's own accounting
      # @return [void]
      def settle(usage)
        return unless usage.is_a?(Hash)

        @main = {
          up:     usage.values_at("input_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens").compact.sum,
          down:   usage["output_tokens"].to_i,
          cached: usage["cache_read_input_tokens"].to_i
        }
      end

      # @param phrase [String, nil]
      # @return [Boolean] whether it published
      def announce(phrase)
        return false if phrase.nil? || phrase == @activity

        @activity = phrase
        publish
        true
      end

      # Hand the caller a whole snapshot rather than the one field that moved.
      # A spinner line draws the phrase and the meter together, and a caller
      # given only the half that changed would have to remember the other.
      #
      # @return [void]
      def publish = @on_progress&.call(progress)
    end
  end
end
