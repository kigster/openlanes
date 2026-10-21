# frozen_string_literal: true

require "fileutils"
require "json"

module OpenLanes
  module Events
    # Appends events to this node's JSONL file: `<dir>/<node id>.jsonl`.
    #
    # One file per node means one writer per file across machines, so no
    # cross-node write can conflict; the report merges files at read time.
    # Two processes on one node (two worktrees) share the file, so each
    # event is one `write` on an `O_APPEND` descriptor, which the kernel
    # keeps whole for a line this short.
    #
    # The sink sits on the dispatcher's tick loop, so it never raises: a
    # full disk or a read-only directory costs a warning, never a tick. It
    # never touches Redis either, so a Redis outage (plan 022.00) cannot
    # take the record down with the live view.
    class Sink
      attr_reader :dir, :node, :checkout, :project, :run

      # @param dir [String] from {Location.dir}
      # @param node [String] {Live::Node#id}
      # @param checkout [String] {Live::Node#checkout_id}
      # @param project [String, nil]
      # @param run [String, nil]
      # @param warn [#call] where a failed write is reported
      # @param clock [#call] the time an event is stamped with
      def initialize(dir:, node:, checkout:, project: nil, run: nil, warn: ->(text) { Kernel.warn(text) },
        clock: -> { Time.now })
        @dir = dir
        @node = node
        @checkout = checkout
        @project = project
        @run = run
        @warn = warn
        @clock = clock
      end

      # @return [Boolean]
      def enabled? = true

      # @return [String]
      def path = File.join(dir, "#{node}.jsonl")

      # The same sink for one run: {Runner} mints the id, everyone it
      # builds emits under it.
      #
      # @param run [String]
      # @return [OpenLanes::Events::Sink]
      def with(run:) = self.class.new(dir:, node:, checkout:, project:, run:, warn: @warn, clock: @clock)

      # Builds the event, its id included, and appends it. `round` and
      # `invocation_start` go into the payload too when the kind carries them.
      #
      # @param kind [String, Symbol]
      # @param plan [String, nil]
      # @param round [Integer, nil]
      # @param agent [String, nil]
      # @param invocation_start [Time, String, nil]
      # @param seq [Object]
      # @param once [Boolean] the fact happens once per plan whatever run
      #   saw it (a PR merged, a question answered), so the run id stays out
      #   of its event id and two runs noticing it dedupe to one
      # @param adapter [String, nil]
      # @param model [String, nil]
      # @param at [Time, nil]
      # @param payload [Hash]
      # @return [OpenLanes::Events::Event, nil] nil when it could not be built or written
      def record(kind, plan: nil, round: nil, agent: nil, invocation_start: nil, seq: 0, once: false, adapter: nil,
        model: nil, at: nil, **payload)
        id = Identity.event_id(node:,
          checkout:,
          plan:,
          round:,
          agent:,
          invocation_start:,
          kind: kind.to_s,
          seq: once ? seq : [run, seq])
        stamp = invocation_start.is_a?(Time) ? invocation_start.utc.iso8601(3) : invocation_start
        known = { round:, invocation_start: stamp }.compact.transform_keys(&:to_s)
                                                   .slice(*Event::PAYLOAD_KEYS.fetch(kind.to_s, []))
        event = Event.new(event_id: id,
          kind:,
          at: at || @clock.call,
          project:,
          plan:,
          run:,
          agent:,
          adapter:,
          model:,
          payload: known.merge(payload.compact.transform_keys(&:to_s)))
        event if emit(event)
      rescue StandardError => e
        @warn.call("openlanes: event #{kind} not recorded (#{e.class}: #{e.message})")
        nil
      end

      # @param event [OpenLanes::Events::Event]
      # @return [Boolean] whether the line landed
      def emit(event)
        FileUtils.mkdir_p(dir)
        File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o644) { it.write("#{event.to_json}\n") }
        true
      rescue StandardError => e
        @warn.call("openlanes: event #{event.kind} not written to #{path} (#{e.class}: #{e.message})")
        false
      end
    end
  end
end
