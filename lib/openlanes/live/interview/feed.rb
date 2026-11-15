# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    class Interview
      # Every interview's turns on one stream ({Keys#interviews}), each with
      # the plan and question it belongs to, so an event stream follows one
      # key, as it follows the copilot's, rather than one per open question.
      class Feed
        # Entries kept, approximately: enough to bridge a page reconnecting.
        LENGTH = 500

        # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
        # @param keys [OpenLanes::Live::Keys]
        def initialize(store:, keys:)
          @store = store
          @keys = keys
        end

        # @param plan [String]
        # @param number [Integer]
        # @param turn [OpenLanes::Live::Interview::Turn]
        # @return [void]
        def append(plan:, number:, turn:)
          json = JSON.generate({ plan:, number:, turn: turn.wire })
          EventBus.for(@store).append(@keys.interviews, { json: }, maxlen: LENGTH)
        end

        # @param after [String] a stream id
        # @return [Array<Array(String, Hash)>] `{plan, number, turn}` after it, oldest first
        def since(after) = @store.xread(@keys.interviews, id: after).map { |entry| [entry.id, JSON.parse(entry.fields["json"])] }

        # @return [String] the newest entry's id, `0-0` when there is none
        def newest = @store.xrevrange(@keys.interviews, count: 1).first&.id || "0-0"
      end
    end
  end
end
