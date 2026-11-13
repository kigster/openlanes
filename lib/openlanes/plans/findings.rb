# frozen_string_literal: true

module OpenLanes
  module Plans
    # The reviewers' findings in a plan's `pull-requests.md`, each under its
    # reviewer's `## Findings: <name>` section and headed
    # `### F<n> [critical|minor] <file>:<line>`, with the ruling a person or
    # the arbitrator last gave it from `state.json`.
    #
    # Reviewers number afresh every review, so a ruling names its finding by
    # id and heading: a ruling whose heading differs is about another F2.
    module Findings
      # One finding as the page shows it: `Finding` in `contract.md`.
      Finding = Data.define(:id, :reviewer, :severity, :file, :line, :heading, :text, :ruling) do
        # @return [Hash]
        def wire = { id:, reviewer:, severity:, file:, line:, text:, ruling: }
      end

      SECTION = /\A##\s+Findings:\s*(?<reviewer>\S.*?)\s*\z/
      HEADING = /\A###\s+(?<id>F\d+)\b\s*(?<heading>.*?)\s*\z/i
      TAG = /\A\[(?<severity>critical|minor)\]\s*/i
      PLACE = %r{(?<file>[^\s:]+\.[\w.]+|[^\s:]+/[^\s:]+):(?<line>\d+)}

      # A verdict a person may give, to the outcome and findings bucket it is
      # written under, so {.ruling} and the reviewer's prompt read it back.
      VERDICTS = { "strike" => %w[struck struck], "accept" => %w[upheld critical] }.freeze

      module_function

      # @param markdown [String] `pull-requests.md`
      # @param rulings [Array<Hash>] `state.json`'s `rulings`
      # @return [Array<Finding>] in the file's order
      def parse(markdown, rulings: [])
        reviewer = nil
        found = []
        markdown.to_s.each_line(chomp: true) do |line|
          if (section = line.match(SECTION)) then reviewer = section[:reviewer]
          elsif line.start_with?("## ") then reviewer = nil
          elsif reviewer && (heading = line.match(HEADING)) then found << start(reviewer, heading)
          elsif found.last && reviewer then found.last[:text] << line
          end
        end
        found.map { |f| build(f, rulings) }
      end

      # @param path [String] the plan folder
      # @return [Array<Finding>]
      def for(path)
        file = File.join(path, PullRequests::FILENAME)
        parse(File.file?(file) ? File.read(file, encoding: "UTF-8") : "", rulings: PlanState.for(path).rulings)
      end

      # The latest ruling on +id+ with +heading+, as `"accept"` or `"strike"`.
      #
      # @param rulings [Array<Hash>]
      # @param id [String]
      # @param heading [String]
      # @return [String, nil]
      def ruling(rulings, id, heading)
        rulings.reverse_each do |ruling|
          named = ruling.dig("findings", "headings", id)
          next if named && named != heading
          return "strike" if Array(ruling.dig("findings", "struck")).include?(id)
          return "accept" if ruling["kind"] == "finding" && Array(ruling.dig("findings", "critical")).include?(id)
        end
        nil
      end

      # @return [Hash] a finding still being read
      def start(reviewer, heading)
        { id: heading[:id].upcase, reviewer:, heading: heading[:heading], text: [] }
      end

      # @return [Finding]
      def build(found, rulings)
        rest = found[:heading]
        place = rest.sub(TAG, "").match(PLACE)
        Finding.new(id: found[:id],
          reviewer: found[:reviewer],
          severity: rest[TAG, :severity]&.downcase || "critical",
          file: place&.[](:file),
          line: place&.[](:line)&.to_i,
          heading: rest,
          text: found[:text].join("\n").strip,
          ruling: ruling(rulings, found[:id], rest))
      end
    end
  end
end
