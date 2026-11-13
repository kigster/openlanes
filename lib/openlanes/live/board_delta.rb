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
      # sent, and its version, which starts at 1 on every connection.
      class Stream
        def initialize
          @sent = nil
          @version = 0
        end

        # @param board [Hash]
        # @return [Array(String, Hash)] the frame to send, as {BoardDelta.frame}
        def next(board)
          @version += 1
          BoardDelta.frame(@sent, board, @version).tap { @sent = board }
        end
      end

      module_function

      # @param before [Hash] a board, `{ me:, others: }`, string or symbol keys
      # @param after [Hash] the same, later
      # @return [Hash] `{ upsert: [{ key:, value: }], remove: [String] }`
      def diff(before, after)
        was = entries(before)
        now = entries(after)
        { upsert: now.reject { |key, value| was[key] == value }.map { |key, value| { key:, value: } },
          remove: was.keys - now.keys }
      end

      # The frame that carries +board+ to a page holding +sent+: the board
      # whole when the page holds none, or when the delta would not be the
      # smaller of the two; otherwise the delta, naming the version it
      # applies onto.
      #
      # @param sent [Hash, nil] the board the page holds, at +version+ - 1
      # @param board [Hash]
      # @param version [Integer] the version +board+ becomes
      # @return [Array(String, Hash)] the event name and its data
      def frame(sent, board, version)
        whole = board.merge(version:)
        return ["board", whole] unless sent

        delta = diff(sent, board).merge(base: version - 1, version:)
        JSON.generate(delta).bytesize < JSON.generate(whole).bytesize ? ["board_delta", delta] : ["board", whole]
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
