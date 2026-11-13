# frozen_string_literal: true

module OpenLanes
  module Adapters
    class Claude < Base
      # What a Claude model costs, and the list this gem shipped with for a
      # machine that cannot ask Anthropic which models exist.
      #
      # Anthropic's Models API names a model, its context window and its
      # output cap, but not its price, so a model this gem has never heard
      # of is priced at its tier's latest known rate and marked
      # {Model#estimated}: a new Opus costs about what the last one did, and
      # "about" is said on the page rather than hidden.
      module Pricing
        # Tiers, cheapest first; a model belongs to the first whose name its
        # id carries.
        TIERS = %w[haiku sonnet opus fable].freeze

        # Dollars per million tokens, in and out, for the newest model of each
        # tier as of 2026-10-13: what a model nobody has priced is assumed to
        # cost. https://platform.claude.com/docs/en/about-claude/pricing
        RATES = {
          "fable"  => [10, 50],
          "opus"   => [4, 20],
          "sonnet" => [2, 10],
          "haiku"  => [0.10, 0.50]
        }.freeze

        # The one-million-token window every current model holds.
        WINDOW = 1_000_000

        # What the gem ships, for a machine that cannot fetch: every model
        # Anthropic served on 2026-10-13, priced from the pricing page, most
        # capable first and newest first within a tier. Haiku 5.5 is priced
        # for prompts up to 100k tokens; above that it is $0.50 in and $2.50
        # out, which this table does not model.
        BUNDLED = [
          Model.new(id: "claude-fable-5-1", label: "Fable 5.1", rate_in: 10, rate_out: 50, context: WINDOW),
          Model.new(id: "claude-fable-5", label: "Fable 5", rate_in: 10, rate_out: 50, context: WINDOW),
          Model.new(id: "claude-opus-5-5", label: "Opus 5.5", rate_in: 4, rate_out: 20, context: WINDOW),
          Model.new(id: "claude-opus-5", label: "Opus 5", rate_in: 5, rate_out: 25, context: WINDOW),
          Model.new(id: "claude-opus-4-8", label: "Opus 4.8", rate_in: 5, rate_out: 25, context: WINDOW),
          Model.new(id: "claude-opus-4-7", label: "Opus 4.7", rate_in: 5, rate_out: 25, context: WINDOW),
          Model.new(id: "claude-opus-4-6", label: "Opus 4.6", rate_in: 5, rate_out: 25, context: WINDOW),
          Model.new(id: "claude-sonnet-5-5", label: "Sonnet 5.5", rate_in: 2, rate_out: 10, context: WINDOW),
          Model.new(id: "claude-sonnet-5", label: "Sonnet 5", rate_in: 2, rate_out: 10, context: WINDOW),
          Model.new(id: "claude-sonnet-4-6", label: "Sonnet 4.6", rate_in: 3, rate_out: 15, context: WINDOW),
          Model.new(id: "claude-haiku-5-5", label: "Haiku 5.5", rate_in: 0.10, rate_out: 0.50, context: WINDOW),
          Model.new(id: "claude-haiku-4-5", label: "Haiku 4.5", rate_in: 1, rate_out: 5, context: 200_000)
        ].freeze

        # A model id with a version: `claude-opus-5-5`, not `claude-opus`,
        # which names a tier and prices nothing.
        VERSIONED = /\Aclaude-[a-z]+-\d/

        module_function

        # The tier a model id belongs to.
        #
        # @param id [String]
        # @return [String, nil] nil for an id naming no tier
        def tier_of(id) = TIERS.find { id.to_s.include?(it) }

        # A model this gem has not priced, at its tier's rate, marked as an
        # estimate; nil for an id in no tier, or one with no version, which
        # nobody can price.
        #
        # @param id [String]
        # @param label [String, nil] what the page shows; derived from the
        #   id when not given (`claude-opus-6` -> `Opus 6`)
        # @param context [Integer, nil]
        # @return [OpenLanes::Adapters::Model, nil]
        def estimate(id, label: nil, context: nil)
          tier = tier_of(id)
          return nil unless tier && id.to_s.match?(VERSIONED)

          rate_in, rate_out = RATES.fetch(tier)
          Model.new(id:, label: label || label_from(id), rate_in:, rate_out:, context: context || WINDOW, estimated: true)
        end

        # `claude-opus-5-5` -> `Opus 5.5`.
        #
        # @param id [String]
        # @return [String]
        def label_from(id)
          name, *version = id.to_s.delete_prefix("claude-").split("-")
          [name.capitalize, version.join(".")].reject(&:empty?).join(" ")
        end

        # Most capable tier first, newest first within it, the id as the tie-break.
        #
        # @param models [Array<OpenLanes::Adapters::Model>]
        # @return [Array<OpenLanes::Adapters::Model>]
        def sort(models)
          models.sort_by { |m| [-TIERS.index(tier_of(m.id)), *version_key(m.id), m.id] }
        end

        # `claude-opus-5-5` -> [-5, -5, 0]: higher versions first, padded so
        # `claude-opus-5` sorts after `claude-opus-5-5`.
        #
        # @param id [String]
        # @return [Array<Integer>]
        def version_key(id)
          digits = id.delete_prefix("claude-").split("-").drop(1).map { Integer(it, exception: false) }.compact
          [-digits.fetch(0, 0), -digits.fetch(1, 0), -digits.fetch(2, 0)]
        end
      end
    end
  end
end
