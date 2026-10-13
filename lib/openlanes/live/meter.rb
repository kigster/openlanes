# frozen_string_literal: true

module OpenLanes
  module Live
    # What each plan has spent this run, kept across the board's rows.
    #
    # A row leaves the board ten seconds after its agent finishes, and what it
    # spent must not leave the plan's total with it. So every row seen is
    # remembered by plan, agent, round and invocation, at the highest figures
    # it showed. The invocation matters because switch_model starts an agent
    # again in the same round, on another model: keyed by round alone, the
    # restart's smaller figures would hide the first run's spend, and the
    # whole round would be priced at the second model.
    class Meter
      # One invocation of an agent's round on one plan, at its latest reading.
      Spend = Data.define(:up, :down, :model)

      def initialize
        @spends = Hash.new { |h, k| h[k] = {} }
        @first_seen = {}
      end

      # @param rows [Array<OpenLanes::Engine::Board::Row>]
      # @param now [Time]
      # @return [void]
      def record(rows, now: Time.now)
        rows.each do |row|
          @first_seen[row.ordinal] ||= now
          key = [row.agent, row.round, row.since]
          known = @spends[row.ordinal][key]
          @spends[row.ordinal][key] =
            Spend.new(up: [row.up.to_i, known&.up.to_i].max, down: [row.down.to_i, known&.down.to_i].max, model: row.model)
        end
      end

      # @param ordinal [String]
      # @return [Time, nil] when this run first saw an agent on the plan
      def started_at(ordinal) = @first_seen[ordinal]

      # @param ordinal [String]
      # @param price [#call] model name to an {Adapters::Model}, or nil
      # @return [Hash{Symbol => Numeric}] `up`, `down` and `cost`
      def for(ordinal, price)
        spends = @spends.fetch(ordinal, {}).values
        { up:   spends.sum(&:up),
          down: spends.sum(&:down),
          cost: spends.sum { |s| price.call(s.model)&.cost(s.up, s.down).to_f }.round(4) }
      end
    end
  end
end
