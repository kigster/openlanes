# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "socket"
require "time"

module OpenLanes
  module Engine
    # The node's progress journal: one append-only NDJSON file per run under
    # {Runtime.journal_dir}, one schema-versioned line per engine event,
    # flushed and fsync'd before {#append} returns. Each line is then mirrored
    # to the {Live::EventBus} on {Live::Keys#journal}.
    #
    # The file is the record, not Redis. {StateFile} is a snapshot rewritten
    # every tick, and the Redis board keeps a hundred entries that vanish with
    # the server, so neither could say what a killed engine had been doing.
    # The bus is best-effort: a publish that raises is reported once and the
    # line stays on disk.
    #
    # Named `EventJournal`, never `Journal`: {Plans::Journal} is the agents'
    # own memory in `state.json`, a different thing that shares the word.
    #
    # @example
    #   journal = EventJournal.new(root: Dir.pwd, run_id: "r1", node: "mbp:abc123")
    #   journal.append(:transition, plan: "003.00", from: "planned", to: "building", event: "build")
    #   EventJournal::Replay.call(journal.path).agents
    class EventJournal
      # The schema every line validates against.
      SCHEMA_PATH = File.expand_path("../../../schemas/journal-event.schema.json", __dir__)

      # The `v` of every line this writer appends. A reader that meets a
      # newer one reports it rather than guessing at the fields.
      VERSION = 1

      # Every `kind` the schema accepts, in the order a run produces them.
      KINDS = %w[
        run_started run_ended plan_assigned agent_started agent_session
        agent_offset agent_ended transition extension question
      ].freeze

      # @return [String] the NDJSON file this journal appends to
      attr_reader :path

      # @return [String]
      attr_reader :run_id

      # @param root [String] the project root, keying {Runtime.journal_dir}
      # @param run_id [String] names the file; one file per run, never truncated
      # @param node [String] this node's `<node id>:<checkout id>`
      # @param bus [Live::EventBus::Base, nil] where each line is mirrored
      # @param channel [String, nil] the bus channel, {Live::Keys#journal}
      # @param clock [#now]
      def initialize(root:, run_id: self.class.run_id, node: self.class.node, bus: nil, channel: nil, clock: Time)
        @run_id = run_id
        @node = node
        @bus = bus
        @channel = channel
        @clock = clock
        @path = File.join(Runtime.journal_dir(root:), "#{run_id}.ndjson")
        @lock = Mutex.new
        @seq = last_seq
        @warned = false
        # O_APPEND, so each line lands whole at the end even beside another
        # writer, and one `write` per line, so a kill tears at most the last.
        @file = File.open(@path, File::WRONLY | File::APPEND | File::CREAT, 0o644)
      end

      # Append one event, durable on return.
      #
      # @param kind [String, Symbol] one of {KINDS}
      # @param fields [Hash] the kind's own fields; `nil` values are kept,
      #   because the schema tells "unknown" from "absent"
      # @return [Hash] the event as written
      # @raise [ArgumentError] on a kind outside {KINDS}
      def append(kind, **fields)
        kind = kind.to_s
        raise ArgumentError, "unknown journal event kind: #{kind}" unless KINDS.include?(kind)

        event = @lock.synchronize do
          @seq += 1
          line = { "v" => VERSION, "seq" => @seq, "at" => @clock.now.utc.iso8601(6), "node" => @node,
                   "run_id" => @run_id, "kind" => kind }.merge(fields.transform_keys(&:to_s))
          @file.write("#{JSON.generate(line)}\n")
          @file.flush
          @file.fsync
          line
        end
        mirror(event)
        event
      end

      # @return [void]
      def close = @lock.synchronize { @file.close unless @file.closed? }

      # @param root [String]
      # @return [String, nil] the most recently written journal under +root+'s runtime directory
      def self.latest(root:)
        Dir.glob(File.join(Runtime.journal_dir(root:), "*.ndjson")).max_by { File.mtime(it) }
      end

      # @param clock [#now]
      # @return [String] `YYYYMMDD-HHMMSS-<6 hex>`, sortable and unique per run
      def self.run_id(clock: Time) = "#{clock.now.utc.strftime("%Y%m%d-%H%M%S")}-#{SecureRandom.hex(3)}"

      # @return [String] the host and this process, when no live node id is known
      def self.node = "#{Socket.gethostname}:#{Process.pid}"

      private

      # A file reopened for the same run carries on numbering where it stopped.
      def last_seq
        return 0 unless File.exist?(@path)

        File.foreach(@path).reduce(0) do |seq, line|
          JSON.parse(line)["seq"].to_i
        rescue JSON::ParserError
          seq
        end
      end

      def mirror(event)
        return unless @bus && @channel

        @bus.publish(@channel, JSON.generate(event))
      rescue StandardError => e
        return if @warned

        @warned = true
        UI.log("journal mirror to the event bus failed (#{e.class}: #{e.message}); the file still has every event")
      end
    end
  end
end
