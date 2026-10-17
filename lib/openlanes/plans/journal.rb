# frozen_string_literal: true

require "json"

module OpenLanes
  module Plans
    # An agent's journal (M2): what it decided, did, left to do, asked and
    # must not forget, kept from one round to the next.
    #
    # The agent writes no file and runs no command. It prints each entry as
    # one line of JSON in its own output, which the harness reads anyway, and
    # the dispatcher keeps it in `state.json` under `memory.<agent>`. One
    # writer, under the lock {PlanState} already takes, is what lets a pair
    # journal at once without either losing the other's line; an agent that
    # wrote the file itself would be a second writer racing the first.
    #
    #     {"openlanes_memory": {"kind": "decision", "text": "Money is integer cents"}}
    #     {"openlanes_memory": {"kind": "override", "text": "BigDecimal after all", "overrides": 3}}
    #
    # The single key {KEY} is what tells an entry from any other JSON an
    # agent prints: a status object, a `package.json` it quotes, a `jq`
    # result. Nothing else an agent has reason to print starts with that key.
    #
    # There is no timestamp. Entries are numbered in order across the
    # agent's rounds on the plan, and a later one wins over an earlier one;
    # an `override` names the number it overturns.
    #
    # Pure: text in, entries out. The dispatcher decides where they go.
    module Journal
      # The one key an entry line carries.
      KEY = "openlanes_memory"

      # What an entry may be. `question` is the agent stopping to ask; the
      # harness adds the answer beside it once one arrives (M3).
      KINDS = %w[todo done decision question override note].freeze

      # Longest text kept, in characters. Every round's prompt carries the
      # journal, so an entry is a line to remember, not a document; one that
      # runs on is cut rather than refused, since what it says first is what
      # it most needed to keep.
      TEXT_LIMIT = 500

      # A line that may be an entry: the key first, after an optional
      # backtick, since agents quote JSON in Markdown as often as not.
      CANDIDATE = /\A`*\{\s*"#{KEY}"\s*:/

      # One entry, as the agent printed it or the harness recorded it.
      #
      # @!attribute [r] kind
      #   @return [String] one of {KINDS}
      # @!attribute [r] text
      #   @return [String]
      # @!attribute [r] overrides
      #   @return [Integer, nil] the number of the entry an `override` overturns
      # @!attribute [r] ref
      #   @return [String, nil] `B<n>`, for a question the harness recorded
      #     from `blocked.md`
      # @!attribute [r] answer
      #   @return [String, nil] a person's answer to that question
      Entry = Data.define(:kind, :text, :overrides, :ref, :answer) do
        def initialize(kind:, text:, overrides: nil, ref: nil, answer: nil) = super

        # @param hash [Hash] as `state.json` keeps it
        # @return [OpenLanes::Plans::Journal::Entry]
        def self.from_h(hash)
          new(kind: hash["kind"].to_s,
            text: hash["text"].to_s,
            overrides: hash["overrides"],
            ref: hash["ref"],
            answer: hash["answer"])
        end

        # @return [Hash] string keys, nils left out, as the schema wants
        def to_json_h = to_h.transform_keys(&:to_s).compact
      end

      # A line that announced itself as an entry and was not one, kept so the
      # dispatcher can say so: an agent whose journal is silently dropped
      # believes it is remembering.
      #
      # @!attribute [r] line
      #   @return [String]
      # @!attribute [r] reason
      #   @return [String]
      Rejection = Data.define(:line, :reason)

      # One round's worth of one agent's journal.
      #
      # @!attribute [r] number
      #   @return [Integer] the agent's journal round on this plan, 1 up,
      #     counted across runs and states. Not the dispatcher's round, which
      #     restarts at 1 in every run and every state and would land a later
      #     run's entries on an earlier run's.
      # @!attribute [r] round
      #   @return [Integer, nil] the dispatcher's round it was printed in
      # @!attribute [r] state
      #   @return [String, nil] the state the plan was in when it started
      # @!attribute [r] entries
      #   @return [Array<Entry>]
      # @!attribute [r] first
      #   @return [Integer] the number of its first entry in the whole journal
      Round = Data.define(:number, :round, :state, :entries, :first)

      module_function

      # Every entry line in one piece of the agent's text, in order, each
      # read into an {Entry} or a {Rejection}. Lines that do not start with
      # {KEY} are none of this method's business and are skipped.
      #
      # @param text [String, nil] what the agent said
      # @return [Array<Entry, Rejection>]
      def scan(text)
        text.to_s.each_line.filter_map do |raw|
          line = raw.strip
          read(line) if line.match?(CANDIDATE)
        end
      end

      # @param line [String] one candidate line
      # @return [Entry, Rejection]
      def read(line)
        json = line.delete_prefix("`" * line[/\A`*/].size).delete_suffix("`" * line[/`*\z/].size)
        value = JSON.parse(json)[KEY]
        problem = problem_with(value)
        return Rejection.new(line:, reason: problem) if problem

        Entry.new(kind: value["kind"], text: clip(value["text"]), overrides: value["overrides"])
      rescue JSON::ParserError => e
        Rejection.new(line:, reason: "not JSON: #{e.message.lines.first.to_s.strip}")
      end

      # Only the fields an agent may set are read; `ref` and `answer` are the
      # harness's to write, and an agent claiming a person answered something
      # is exactly the line that must not be trusted.
      #
      # @param value [Object]
      # @return [String, nil] why it is not an entry
      def problem_with(value)
        return "#{KEY} is not an object" unless value.is_a?(Hash)
        return "kind #{value["kind"].inspect} is not one of #{KINDS.join(", ")}" unless KINDS.include?(value["kind"])
        return "text is missing" unless value["text"].is_a?(String) && !value["text"].strip.empty?

        overrides = value["overrides"]
        return nil if overrides.nil?
        return "overrides must be an entry number" unless overrides.is_a?(Integer) && overrides.positive?

        "only an override may name an entry it overrides" unless value["kind"] == "override"
      end

      # @param text [String]
      # @return [String] stripped, and cut to {TEXT_LIMIT}
      def clip(text)
        text = text.to_s.strip
        text.length > TEXT_LIMIT ? "#{text[0, TEXT_LIMIT - 1]}…" : text
      end

      # The line an agent prints, for the prompt's examples, so the prompt and
      # the parser cannot describe two shapes.
      #
      # @param kind [String]
      # @param text [String]
      # @param overrides [Integer, nil]
      # @return [String]
      def line(kind, text, overrides: nil)
        JSON.generate(KEY => { "kind" => kind, "text" => text, "overrides" => overrides }.compact)
      end
    end
  end
end
