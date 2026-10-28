# frozen_string_literal: true

module OpenLanes
  module Adapters
    # One model an adapter offers: what the page lists in a car's dropdown,
    # and what a token costs on it.
    #
    # @!attribute [r] id
    #   @return [String] the full model id, e.g. `claude-sonnet-5-5`
    # @!attribute [r] label
    #   @return [String] e.g. `Sonnet 5.5`
    # @!attribute [r] rate_in
    #   @return [Numeric, nil] dollars per million tokens sent; nil for a
    #     model a CLI lists but nobody has priced
    # @!attribute [r] rate_out
    #   @return [Numeric, nil] dollars per million tokens generated
    # @!attribute [r] context
    #   @return [Integer] tokens the model's context window holds, the
    #     ceiling a car's context meter is drawn against
    Model = Data.define(:id, :label, :rate_in, :rate_out, :context) do
      def initialize(context: Model::WINDOW, rate_in: nil, rate_out: nil, **rest) = super

      # Built back from {#wire}, as {Availability.from_wire} reads it out of Redis.
      #
      # @param hash [Hash{String => Object}]
      # @return [OpenLanes::Adapters::Model]
      def self.from_wire(hash)
        rates = hash["rates"] || {}
        new(id: hash.fetch("id"),
          label: hash.fetch("label"),
          rate_in: rates["in"],
          rate_out: rates["out"],
          context: hash["context"] || Model::WINDOW)
      end

      # @return [Boolean] whether a token on this model has a price
      def priced? = !(rate_in.nil? || rate_out.nil?)

      # @param up [Integer] tokens in
      # @param down [Integer] tokens out
      # @return [Float] dollars; 0.0 on a model nobody has priced
      def cost(up, down) = priced? ? ((up.to_i * rate_in) + (down.to_i * rate_out)) / 1_000_000.0 : 0.0

      # The `ModelChoice` of `web/src/api/types.ts`. The context window rides
      # along: left off, a model read back out of Redis would shrink to
      # {WINDOW}, and codex's 272k models with it.
      #
      # @return [Hash]
      def wire = { id:, label:, rates: priced? ? { in: rate_in, out: rate_out } : nil, context: }
    end

    # The context window a model gets when its entry names none: every
    # model the adapters price today holds this many tokens.
    Model::WINDOW = 200_000
  end
end
