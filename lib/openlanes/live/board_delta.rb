# frozen_string_literal: true

module OpenLanes
  module Live
    # What changed between two boards (`Live.board`), as the event stream's
    # `board_delta` frame carries it. A full board grows with every plan and
    # every machine, and resending it each tick for one car's token count is
    # most of what the stream sent.
    #
    # The board is flattened into keyed entries: one per node, holding its
    # snapshot without `plans` but with `plan_order`, and one per plan. A
    # delta is the entries that differ and the keys that went. The page
    # applies it by key and rebuilds each snapshot's `plans` from its order.
    module BoardDelta
      # One event stream's side of the exchange: the board the page was last
      # sent, flattened once and kept, and its version, which starts at 1 on
      # every connection.
      #
      # The flattened board and each entry's size are kept across ticks
      # because a tick with ten tabs open ran the whole board through JSON
      # several times per tab for one car's token count: once to flatten
      # what was sent before, and twice more to measure the delta against
      # the whole. An unchanged entry is now measured once, when it arrives.
      class Stream
        def initialize
          @held = nil
          @sizes = {}
          @version = 0
        end

        # @param board [Hash] `{ me:, others: }`, as {Live.board} returns it
        # @return [Array(String, Hash)] the event name and its data: the
        #   board whole when the page holds none, or when the delta would not
        #   be the smaller of the two; otherwise the delta, naming the version
        #   it applies onto
        def next(board)
          @version += 1
          now = BoardDelta.entries(board)
          frame = frame_for(now, board)
          @held = now
          frame
        end

        private

        # @param now [Hash{String => Hash}] the board's entries
        # @param board [Hash]
        # @return [Array(String, Hash)]
        def frame_for(now, board)
          measure(now)
          whole = board.merge(version: @version)
          return ["board", whole] unless @held

          delta = BoardDelta.changes(@held, now)
          smaller?(delta) ? ["board_delta", delta.merge(base: @version - 1, version: @version)] : ["board", whole]
        end

        # Keeps each entry's JSON size, measuring only what changed. The first
        # board is measured too, so the first delta measures only its changes.
        #
        # @param now [Hash{String => Hash}]
        # @return [void]
        def measure(now)
          @sizes = now.to_h { |key, value| [key, (@sizes[key] if @held&.[](key) == value) || JSON.generate(value).bytesize] }
        end

        # Whether the delta is the smaller frame, estimated from the entries'
        # own sizes rather than by serialising both frames: the keys and
        # braces around them are left out of both sides. A wrong guess costs
        # bytes, never correctness, since the page takes either frame.
        #
        # @param delta [Hash] as {BoardDelta.changes}
        # @return [Boolean]
        def smaller?(delta)
          sent = delta[:upsert].sum { @sizes.fetch(it[:key]) } + delta[:remove].sum(&:bytesize)
          sent < @sizes.each_value.sum
        end
      end

      module_function

      # @param before [Hash] a board, `{ me:, others: }`, string or symbol keys
      # @param after [Hash] the same, later
      # @return [Hash] `{ upsert: [{ key:, value: }], remove: [String] }`
      def diff(before, after) = changes(entries(before), entries(after))

      # @param was [Hash{String => Hash}] entries, as {.entries}
      # @param now [Hash{String => Hash}]
      # @return [Hash] `{ upsert: [{ key:, value: }], remove: [String] }`
      def changes(was, now)
        { upsert: now.reject { |key, value| was[key] == value }.map { |key, value| { key:, value: } },
          remove: was.keys - now.keys }
      end

      # @param board [Hash]
      # @return [Hash{String => Hash}] key to entry, in board order
      def entries(board)
        board = JSON.parse(JSON.generate(board))
        [board["me"], *board["others"]].compact.each_with_object({}) do |snapshot, out|
          node = "#{snapshot.dig("node", "id")}/#{snapshot.dig("node", "checkout")}"
          plans = Array(snapshot["plans"])
          out["node/#{node}"] = snapshot.except("plans").merge("plan_order" => plans.map { it["ordinal"] })
          plans.each { |plan| out["plan/#{node}/#{plan["ordinal"]}"] = plan }
        end
      end
    end
  end
end
