# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes review PR LABEL` — move a pull request to its next review label.
    #
    # The one door through which a review label is set. Agents may not run
    # `gh pr edit`, so a verdict reaches GitHub only by passing the CI rule in
    # {Vcs::Review}, and this command is where a person, or staff-reviewer, asks.
    class Review < Base
      desc "Replace a pull request's review label, refusing a passing verdict while CI is red"

      argument :pull_request, required: true, desc: "Pull request number or URL, e.g. 12, #12"
      argument :label,
        required: true,
        values:   Plans::ReviewLabel.names,
        desc:     "One of: #{Plans::ReviewLabel.names.join(", ")}"

      dry_run_option "Compute the transition and write nothing to GitHub"

      example [
        "12 #{Plans::ReviewLabel::INITIAL.name}   # label PR #12",
        "12 #{Plans::ReviewLabel::REJECTED.name} -n   # what that would do"
      ]

      # @param pull_request [String]
      # @param label [String]
      # @param options [Hash]
      # @return [void]
      def call(pull_request:, label:, **options)
        quiet?(options)
        begin
          # Checked here so a typo is a usage error, not a `gh` failure.
          Plans::ReviewLabel.fetch(label)
        rescue OpenLanes::Error => e
          refuse(e.message, 64)
        end

        result = begin
          Vcs.review.call(pr: pull_request, label:, dry_run: dry_run?(options))
        rescue OpenLanes::Error => e
          refuse(e.message, 69)
        end
        report(result)
        exit 1 if result.refused?
      end

      private

      # The deliverable on STDOUT, one tab-separated line, and the reading of
      # it on STDERR.
      #
      # @param result [OpenLanes::Vcs::Review::Result]
      # @return [void]
      def report(result)
        from = result.from.empty? ? "(none)" : result.from.join(", ")
        puts "#{result.pr}\t#{from}\t#{result.to}\t#{result.ci}\t#{result.refused? ? "refused" : "ok"}"

        if result.refused?
          error("PR ##{result.pr} stays #{from}: #{result.reason}.\n" \
                "Only #{Plans::ReviewLabel::REJECTED.name} and #{Plans::ReviewLabel::VULNERABILITY.name} " \
                "are accepted until CI is green.")
          return
        end

        say("PR ##{result.pr}: #{from} → #{paint(result.to, :green)} (CI #{result.ci})")
        warn(result.reason) if result.reason
        dry_run_footer(1, "label change") if result.dry_run?
      end
    end
  end
end
