# frozen_string_literal: true

module OpenLanes
  module Agents
    # Which coding agent the project gives an agent that names none of its
    # own: its `adapter:` (plan 040), except for the reviewers (plan 031, V7
    # and D12), which are dealt across `review.adapters` in {ORDER}, staff to the
    # first, security to the second, design to the third, wrapping when the
    # list is shorter. Three reviewers on three coding agents see the diff
    # through three different models, which is the point of having three.
    #
    # An adapter the startup probe found unusable is skipped before dealing,
    # so a signed-out CLI moves its reviewer to the next one rather than
    # failing it. Only the probe's "no" counts: an adapter not yet probed is
    # dealt as usual.
    #
    # Both sit below an agent's own `adapter:` and the plan's `phases.<phase>`
    # in {Profile.resolve}'s precedence.
    #
    # A reviewer named in +replacing+ failed its round, and runs it again on
    # the main coding agent (D14 in plan 031). That sits above everything,
    # because the adapter that failed it may be the one the plan asked for.
    #
    # @example
    #   dealing = Dealing.new(adapters: %w[claude codex], fallback: "pi")
    #   dealing.adapter_for(registry.find("design-reviewer")) # => "claude"
    #   dealing.adapter_for(registry.find("planner"))         # => "pi"
    class Dealing
      # The seats, in the order they are dealt. A reviewer a project adds
      # beyond these takes the seat after the last.
      ORDER = %w[staff-reviewer security-reviewer design-reviewer].freeze

      # Every adapter usable: what a run without the probe's answers assumes.
      ANY = ->(_name) { true }

      # The project's own: `review.adapters` and `adapter:` from `.openlanes.yml`.
      #
      # @param usable [#call]
      # @param replacing [Array<String>] reviewers running a failed round again
      # @return [OpenLanes::Agents::Dealing]
      def self.current(usable: ANY, replacing: [])
        config = Config.current
        new(adapters: config.review_adapters, fallback: config.adapter, usable:, replacing:)
      end

      # @param adapters [Array<String>] `review.adapters`, main one first
      # @param fallback [String, nil] `adapter:`, for everything not dealt
      # @param usable [#call] adapter name → whether the probe left it usable
      # @param replacing [Array<String>] reviewers running a failed round again
      def initialize(adapters: [], fallback: nil, usable: ANY, replacing: [])
        @adapters = adapters
        @fallback = fallback
        @usable = usable
        @replacing = replacing
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @return [String, nil] the adapter dealt to a reviewer, else the
      #   fallback; nil leaves {Adapters::DEFAULT}
      def adapter_for(agent) = dealt(agent) || fallback

      # The main coding agent (I2): `adapter:`, else {Adapters::DEFAULT}.
      #
      # @return [String]
      def main = fallback || Adapters::DEFAULT

      # @param agent [OpenLanes::Agents::Agent]
      # @return [String, nil] {#main} for a reviewer running a failed round
      #   again, nil for every other agent
      def replacement_for(agent) = (main if replacing.include?(agent.name))

      private

      # @return [Array<String>]
      attr_reader :adapters

      # @return [String, nil]
      attr_reader :fallback

      # @param agent [OpenLanes::Agents::Agent]
      # @return [String, nil] nil for an agent that does not review, or when
      #   no listed adapter is usable
      def dealt(agent)
        return nil unless agent.phase.to_s == Engine::Reviews::PHASE

        seats = adapters.select { usable.call(it) }
        seats[(ORDER.index(agent.name) || ORDER.size) % seats.size] unless seats.empty?
      end

      # @return [#call]
      attr_reader :usable

      # @return [Array<String>]
      attr_reader :replacing
    end
  end
end
