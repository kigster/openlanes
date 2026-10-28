# frozen_string_literal: true

module OpenLanes
  module Adapters
    # Whether one CLI can take an agent on this machine right now, as its
    # {Base#probe} found it: installed, signed in, and with a model to run.
    #
    # The page draws an adapter that is not available disabled, with
    # {#reason} beside it (Q2), so the reason is written for a person.
    #
    # @!attribute [r] name
    #   @return [String] the adapter's name, as {Adapters.names} spells it
    # @!attribute [r] available
    #   @return [Boolean, nil] nil until a probe has run
    # @!attribute [r] reason
    #   @return [String, nil] why it is not available; nil when it is
    # @!attribute [r] models
    #   @return [Array<OpenLanes::Adapters::Model>] what it offers, most capable first
    # @!attribute [r] checked_at
    #   @return [Time, nil] when the probe ran; nil until one has
    Availability = Data.define(:name, :available, :reason, :models, :checked_at) do
      # @param name [String]
      # @param models [Array<OpenLanes::Adapters::Model>]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def self.up(name, models, at) = new(name:, available: true, reason: nil, models:, checked_at: at)

      # @param name [String]
      # @param reason [String]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def self.down(name, reason, at) = new(name:, available: false, reason:, models: [], checked_at: at)

      # What the page shows before the first probe has answered: the
      # adapter's own priced models, and no verdict either way.
      #
      # @param adapter [OpenLanes::Adapters::Base]
      # @return [OpenLanes::Adapters::Availability]
      def self.unchecked(adapter) = new(name: adapter.name, available: nil, reason: nil, models: adapter.models, checked_at: nil)

      # Built back from {#wire}, as {Probes} reads it out of Redis.
      #
      # @param hash [Hash{String => Object}]
      # @return [OpenLanes::Adapters::Availability]
      def self.from_wire(hash)
        new(name: hash.fetch("name"),
          available: hash["available"],
          reason: hash["reason"],
          models: Array(hash["models"]).map { Model.from_wire(it) },
          checked_at: hash["checked_at"] && Time.iso8601(hash["checked_at"]))
      end

      # @return [Boolean]
      def available? = available == true

      # The `AdapterAvailability` of `web/src/api/types.ts`, less the
      # capabilities {Live::Snapshot} adds.
      #
      # @return [Hash]
      def wire = { name:, available:, reason:, models: models.map(&:wire), checked_at: checked_at&.utc&.iso8601 }
    end
  end
end
