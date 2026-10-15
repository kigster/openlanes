# frozen_string_literal: true

require "time"

module OpenLanes
  module Plans
    # What an interrupted agent had done, as a record the next round acts on.
    #
    # It replaces the `RESUME: ...` mail, which was prose the next agent had
    # to read and believe. The fields are fixed: freeform JSON would be prose
    # with braces, and no easier to act on.
    #
    # Two writers. The agent, through `openlanes state resume`, when it
    # reaches a polling point after INTERRUPT. The harness, when the agent
    # never did: killed when GRACE ran out, or dead outright. The agent knows
    # what it did, the harness only what it saw, so an agent's entry is never
    # replaced by a harness one from the same round or an earlier one.
    #
    # Pids, tokens and exit codes are not here and cannot be: this lands in
    # the committed `state.json`, and process detail belongs to one machine's
    # `openlanes-state.json`.
    #
    # @!attribute [r] source
    #   @return [String] "agent" or "harness"
    # @!attribute [r] at
    #   @return [String] ISO 8601
    # @!attribute [r] round
    #   @return [Integer]
    # @!attribute [r] status
    #   @return [String] one of {Ledger::STATUSES}
    # @!attribute [r] done
    #   @return [Array<String>]
    # @!attribute [r] remaining
    #   @return [Array<String>]
    # @!attribute [r] next_step
    #   @return [String, nil] the one thing to do first
    # @!attribute [r] files_touched
    #   @return [Array<String>]
    # @!attribute [r] note
    #   @return [String, nil] what the harness saw, for a harness entry
    LastKnownState = Data.define(:source, :at, :round, :status, :done, :remaining, :next_step, :files_touched, :note) do
      # @return [Array<String>]
      def self.sources = %w[agent harness]

      # @param hash [Hash] as `state.json` holds it
      # @return [OpenLanes::Plans::LastKnownState]
      def self.from_h(hash)
        new(**members.to_h { |k| [k, hash[k.to_s]] }.compact)
      end

      # @raise [OpenLanes::Error] for a source or status outside the vocabulary
      def initialize(source:, round:, status:, at: Time.now.iso8601, done: [], remaining: [], next_step: nil,
        files_touched: [], note: nil)
        raise Error, "source must be one of #{self.class.sources.join(", ")}" unless self.class.sources.include?(source)
        raise Error, "status must be one of #{Ledger::STATUSES.join(", ")}" unless Ledger::STATUSES.include?(status)

        super(source:, at: at.respond_to?(:iso8601) ? at.iso8601 : at.to_s, round: Integer(round), status:,
          done: Array(done), remaining: Array(remaining), next_step:, files_touched: Array(files_touched), note:)
      end

      # @return [Boolean]
      def agent? = source == "agent"

      # Whether this entry may replace +other+, the one already kept. An
      # agent's entry replaces anything; the harness's only what is not an
      # agent's of the same round or later.
      #
      # @param other [OpenLanes::Plans::LastKnownState, nil]
      # @return [Boolean]
      def supersedes?(other)
        return true if other.nil? || agent?

        !(other.agent? && other.round >= round)
      end

      # @return [Hash] as `state.json` holds it, empty fields left out
      def to_json_h
        to_h.transform_keys(&:to_s).reject { |_, v| v.nil? || v == [] }
      end
    end
  end
end
