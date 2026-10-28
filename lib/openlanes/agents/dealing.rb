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
      # @return [OpenLanes::Agents::Dealing]
      def self.current(usable: ANY)
        config = Config.current
        new(adapters: config.review_adapters, fallback: config.adapter, usable:)
      end

      # @param adapters [Array<String>] `review.adapters`, main one first
      # @param fallback [String, nil] `adapter:`, for everything not dealt
      # @param usable [#call] adapter name → whether the probe left it usable
      def initialize(adapters: [], fallback: nil, usable: ANY)
        @adapters = adapters
        @fallback = fallback
        @usable = usable
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @return [String, nil] the adapter dealt to a reviewer, else the
      #   fallback; nil leaves {Adapters::DEFAULT}
      def adapter_for(agent) = dealt(agent) || fallback

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
    end
  end
end
