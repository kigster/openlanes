# frozen_string_literal: true

module OpenLanes
  module Events
    # What one invocation spent, as the log keeps it.
    #
    # Only claude prices its models, and even its price ignores cache reads
    # and writes, so every cost here is an estimate and says so. Codex and
    # pi have no price table: their cost is nil, never 0, because `Meter`
    # pricing them at 0 is exactly how unpriced spend came to read as free.
    # `total_cost_usd` is never read; its semantics under stream-json are
    # disputed (spec, Research Q4).
    #
    # @!attribute [r] adapter
    #   @return [String]
    # @!attribute [r] cost_usd
    #   @return [Float, nil] nil when the adapter prices nothing
    # @!attribute [r] estimated
    #   @return [Boolean] true on every computed cost
    # @!attribute [r] incomplete
    #   @return [Boolean] true when sub-agents spent outside the `result` figure
    Usage = Data.define(:adapter,
      :input_tokens,
      :output_tokens,
      :cache_read_tokens,
      :cache_write_tokens,
      :cost_usd,
      :estimated,
      :incomplete) do
      # @return [Hash{String => Object}] the {Event::USAGE_KEYS} of an `agent_finished`
      def to_h = super.except(:adapter).transform_keys(&:to_s)
    end

    class Usage
      # Adapters whose models carry a price.
      PRICED = %w[claude].freeze

      class << self
        # @param adapter [String, Symbol]
        # @param model [String, nil]
        # @param totals [Hash] the adapter's accounting; read defensively,
        #   since field names vary by CLI version
        # @param subagents_spawned [Integer]
        # @param price [#call] model name to an {Adapters::Model}, or nil
        # @return [OpenLanes::Events::Usage]
        def from(adapter:, model:, totals:, subagents_spawned: 0, price: nil)
          name = adapter.to_s
          figures = totals.to_h.transform_keys(&:to_s)
          input = count(figures, "input_tokens", "up")
          output = count(figures, "output_tokens", "down")
          cost = PRICED.include?(name) ? cost_of(name, model, input, output, price) : nil
          new(adapter: name,
            input_tokens: input,
            output_tokens: output,
            cache_read_tokens: count(figures, "cache_read_input_tokens", "cache_read_tokens", "cached_input_tokens"),
            cache_write_tokens: count(figures, "cache_creation_input_tokens", "cache_write_tokens"),
            cost_usd: cost,
            estimated: !cost.nil?,
            incomplete: name == "claude" && subagents_spawned.to_i.positive?)
        end

        private

        # @return [Integer, nil] the first key present, nil when none is
        def count(figures, *keys)
          key = keys.find { figures[it].is_a?(Numeric) }
          key && figures[key].to_i
        end

        # @return [Float, nil]
        def cost_of(adapter, model, input, output, price)
          return nil if input.nil? && output.nil?

          entry = price ? price.call(model) : Adapters.for(adapter).model_entry(model)
          entry&.cost(input, output)&.round(6)
        rescue StandardError
          nil
        end
      end
    end
  end
end
