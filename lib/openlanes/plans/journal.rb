# frozen_string_literal: true

require "json"

module OpenLanes
  module Plans
    # An agent's journal (M2): what it decided, did, asked and must not
    # forget, printed as it happens, one line of JSON each, in its own output:
    #
    #   {"kind":"decision","text":"tokens live in Redis, not Postgres"}
    #   {"kind":"override","text":"tokens live in Postgres after all","overrides":3}
    #
    # The agent writes no file and runs no command. The dispatcher reads the
    # lines out of the stream and is the only writer of them into
    # `state.json`, under `memory.<agent>.rounds.<n>`, so a pair working at
    # once cannot collide, and a killed agent keeps every line it printed.
    #
    # There is no timestamp: the list is ordered, and a later entry wins
    # over an earlier one. Entries are numbered per agent across its rounds,
    # so an override in round 3 can name a decision taken in round 1.
    module Journal
      # Every kind an entry may have. Anything else on a line is not an entry.
      KINDS = %w[todo done decision question override note].freeze

      # The keys a printed entry may carry. A line with any other key is the
      # agent printing some JSON of its own, not a journal entry.
      KEYS = %w[kind text overrides].freeze

      # One entry as printed, before the dispatcher numbers it.
      #
      # @!attribute [r] kind
      #   @return [String] one of {KINDS}
      # @!attribute [r] text
      #   @return [String]
      # @!attribute [r] overrides
      #   @return [Integer, nil] the number of the entry an override overturns
      Entry = Data.define(:kind, :text, :overrides) do
        def initialize(kind:, text:, overrides: nil) = super

        # @param number [Integer] the entry's number in its agent's journal
        # @return [Hash] as kept in `state.json`
        def to_json_h(number) = { "number" => number, "kind" => kind, "text" => text, "overrides" => overrides }.compact
      end

      module_function

      # The entries in a block of the agent's text, in the order printed.
      # Each must be a line on its own: an entry quoted inside a sentence is
      # the agent talking about the journal, not writing in it.
      #
      # @param text [String, nil]
      # @return [Array<OpenLanes::Plans::Journal::Entry>]
      def scan(text) = text.to_s.each_line.filter_map { entry(it) }

      # @param line [String]
      # @return [OpenLanes::Plans::Journal::Entry, nil] nil for anything but an entry
      def entry(line)
        stripped = line.strip.delete_prefix("`").delete_suffix("`")
        return nil unless stripped.start_with?("{") && stripped.end_with?("}")

        data = JSON.parse(stripped)
        return nil unless data.is_a?(Hash) && (data.keys - KEYS).empty?

        kind = data["kind"]
        body = data["text"]
        return nil unless KINDS.include?(kind) && body.is_a?(String) && !body.strip.empty?

        overrides = data["overrides"]
        return nil if kind == "override" && !(overrides.is_a?(Integer) && overrides.positive?)

        Entry.new(kind:, text: body.strip, overrides: kind == "override" ? overrides : nil)
      rescue JSON::ParserError
        nil
      end

      # A round's entries as the next round's prompt shows them.
      #
      # @param entries [Array<Hash>] as kept in `state.json`
      # @return [String] one line per entry, empty when there are none
      def render(entries)
        entries.map do |e|
          over = e["overrides"] ? " (overrides ##{e["overrides"]})" : ""
          "  ##{e["number"]} #{e["kind"]}#{over}: #{e["text"]}"
        end.join("\n")
      end
    end
  end
end
