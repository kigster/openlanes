# frozen_string_literal: true

require "yaml"

module OpenLanes
  module Arbitration
    # One ruling, read from the fenced `ruling` block the arbitrator ends
    # its answer with. The engine, not the agent, records and applies it
    # (M7), so a block that cannot be read is refused by name rather than
    # guessed at: a guessed ruling would move a plan nobody ruled on.
    #
    # `headings` maps a struck id to the rest of its entry, when the
    # arbitrator wrote one (`F2 lib/a.rb:10 asks for an out-of-scope test`):
    # staff-reviewer numbers its findings afresh in every review, so an id alone
    # names a different finding a round later.
    class Ruling < Data.define(:kind, :pr, :outcome, :struck, :critical, :winner, :reason, :headings)
      # The outcomes each kind may give.
      OUTCOMES = {
        "cap"          => %w[go no_go],
        "appeal"       => %w[upheld struck],
        "dispute"      => Agents::Names::BUILDERS,
        "passed_check" => %w[fair too_harsh too_lenient]
      }.freeze

      # One entry of `findings.struck` or `findings.critical`: an id, then
      # optionally the finding's heading.
      ENTRY = /\A(F\d+)\b[ \t:-]*(.*)\z/i

      # The fenced block, with `ruling` as its info string.
      BLOCK = /^```ruling[ \t]*\n(.*?)^```[ \t]*$/m

      # The answer carried no `ruling` block.
      class Missing < Error; end

      # The answer carried more than one, or one that is not a YAML mapping.
      class Ambiguous < Error; end

      # The kind is unknown, or the outcome is not one its kind may give.
      class IllegalOutcome < Error; end

      class << self
        # @param text [String, nil] the adapter's final text
        # @return [Ruling]
        # @raise [Ruling::Missing, Ruling::Ambiguous, Ruling::IllegalOutcome]
        def parse(text)
          blocks = text.to_s.scan(BLOCK).map(&:first)
          raise Missing, "the answer has no ```ruling block" if blocks.empty?
          raise Ambiguous, "the answer has #{blocks.size} ```ruling blocks; one is read" if blocks.size > 1

          from(load(blocks.first))
        end

        private

        # @param yaml [String]
        # @return [Hash]
        def load(yaml)
          data = YAML.safe_load(yaml)
          raise Ambiguous, "the ruling block is not a YAML mapping" unless data.is_a?(Hash)

          data.transform_keys(&:to_s)
        rescue Psych::SyntaxError => e
          raise Ambiguous, "the ruling block is not YAML: #{e.message}"
        end

        # @param data [Hash]
        # @return [Ruling]
        def from(data)
          kind = data["kind"].to_s
          outcomes = OUTCOMES[kind] or raise IllegalOutcome, "unknown ruling kind #{kind.inspect}"
          # A dispute's outcome is its winner: one word, two places to read it.
          outcome = (data["outcome"] || (data["winner"] if kind == "dispute")).to_s
          raise IllegalOutcome, "#{kind} cannot rule #{outcome.inspect}" unless outcomes.include?(outcome)

          findings = data["findings"].is_a?(Hash) ? data["findings"].transform_keys(&:to_s) : {}
          struck = entries(findings["struck"])
          new(kind:,
            pr:       data["pr"] && Integer(data["pr"], exception: false),
            outcome:,
            struck:   struck.keys,
            critical: entries(findings["critical"]).keys,
            winner:   kind == "dispute" ? outcome : nil,
            reason:   data["reason"].to_s.strip,
            headings: struck.reject { |_, heading| heading.empty? })
        end

        # @param list [Array, String, nil]
        # @return [Hash{String => String}] finding id, upper-cased, to the
        #   heading written after it (empty when none was)
        def entries(list)
          Array(list).filter_map { it.to_s.strip.match(ENTRY) }.to_h { [it[1].upcase, it[2].strip] }
        end
      end

      # @param headings [Hash{String => String}] defaults to none, so a
      #   ruling built by hand needs no headings
      def initialize(headings: {}, **) = super

      # @return [Hash] the `findings` entry {Plans::PlanState#rule!} takes
      def findings = { "struck" => struck, "critical" => critical, "headings" => (headings unless headings.empty?) }.compact

      # @return [String] the line the engine's PR comment opens with
      def headline = "⚖️ Ruling (#{kind}): #{outcome}"
    end
  end
end
