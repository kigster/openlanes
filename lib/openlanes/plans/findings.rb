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
      # This table is the one place the vocabulary lives: {.rule!}, the demo
      # board, {Arbitration::Ruling::OUTCOMES} and {Engine::Arbitration} all
      # read it, so a new verdict is written once.
      VERDICTS = { "strike" => %w[struck struck], "accept" => %w[upheld critical] }.freeze

      # The ruling kind a person's verdict is written under, beside the
      # arbitrator's `appeal` and `cap`.
      KIND = "finding"

      # The outcomes a `finding` ruling may carry, for {Arbitration::Ruling}.
      OUTCOMES = VERDICTS.values.map(&:first).freeze

      # The `findings` buckets a ruling names findings in.
      BUCKETS = VERDICTS.values.map(&:last).freeze

      # The verdict is not one of {VERDICTS}.
      class UnknownVerdict < Error; end

      # No finding of that id in the plan's `pull-requests.md`.
      class NotFound < Error; end

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
      # A strike counts whoever gave it: the arbitrator strikes through an
      # `appeal` ruling. An acceptance counts only from a person, since the
      # arbitrator's `cap` ruling lists critical findings it did not rule on.
      #
      # @param rulings [Array<Hash>]
      # @param id [String]
      # @param heading [String]
      # @return [String, nil]
      def ruling(rulings, id, heading)
        rulings.reverse_each do |ruling|
          named = ruling.dig("findings", "headings", id)
          next if named && named != heading

          VERDICTS.each do |verdict, (outcome, bucket)|
            next unless Array(ruling.dig("findings", bucket)).include?(id)
            return verdict if outcome == "struck" || ruling["kind"] == KIND
          end
        end
        nil
      end

      # @param verdict [Object] what a person sent
      # @return [String] the verdict, one of {VERDICTS}' keys
      # @raise [UnknownVerdict]
      def verdict!(verdict)
        return verdict if VERDICTS.key?(verdict)

        raise UnknownVerdict, "verdict must be #{VERDICTS.keys.sort.join(" or ")}, not #{verdict.inspect}"
      end

      # @param findings [Array<Finding>] a plan's, as {.for} reads them
      # @param id [String] e.g. "f2"; case does not matter
      # @param plan [String] the plan's number, for the error
      # @return [Finding] the latest one with that id
      # @raise [NotFound]
      def find!(findings, id, plan:)
        findings.rfind { it.id == id.to_s.upcase } or raise NotFound, "#{plan} has no finding #{id}"
      end

      # The ruling a person's verdict on +finding+ is written as, in the shape
      # {PlanState#rule!} takes: the engine writes it to `state.json` and the
      # demo board keeps it in memory, and both must read back the same way.
      #
      # @param finding [Finding]
      # @param verdict [String] one of {VERDICTS}' keys
      # @param by [String] who ruled
      # @return [Hash] keyword arguments for {PlanState#rule!}
      def ruling_for(finding, verdict, by:)
        outcome, bucket = VERDICTS.fetch(verdict!(verdict))
        { kind:     KIND,
          pr:       nil,
          round:    nil,
          outcome:,
          winner:   nil,
          trigger:  "person",
          findings: { bucket => [finding.id], "headings" => { finding.id => finding.heading } },
          reason:   "#{verdict} by #{by}" }
      end

      # Writes a person's verdict into the plan's `state.json`, where the
      # arbitrator's rulings go, so a struck finding is never raised again.
      #
      # @param path [String] the plan folder
      # @param finding [Finding]
      # @param verdict [String]
      # @param by [String]
      # @return [Hash] the ruling written
      # @raise [UnknownVerdict]
      def rule!(path, finding, verdict, by:)
        PlanState.for(path).rule!(**ruling_for(finding, verdict, by:))
      end

      # @param ruling [Hash] one of `state.json`'s `rulings`
      # @param id [String]
      # @return [Boolean] whether a person ruled on finding +id+ in it
      def rules?(ruling, id)
        ruling["kind"] == KIND && BUCKETS.any? { Array(ruling.dig("findings", it)).include?(id) }
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
