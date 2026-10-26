# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes eval` — score the agents against their cases.
    #
    # Offline by default: every case's recorded folder is scored, which costs
    # nothing and runs in CI. `--live` runs the real agents and is never the
    # default, because it spends tokens.
    class Eval < Base
      standalone!
      desc "Score agents against evals/cases: recorded folders by default, real runs with --live"

      argument :name, required: false, desc: "Only this agent's cases, as `--agent` says it"
      option :agent, aliases: ["-a"], desc: "Only this agent's cases"
      option :case, aliases: ["-c"], desc: "Only the case with this id"
      option :depth,
        values: Plans::Spec::DEPTHS.map(&:to_s),
        desc:   "Hold every case to this depth's bounds instead of its own"
      option :recording,
        values:  %w[pass fail],
        default: "pass",
        desc:    "Which recording to score offline"
      option :live,
        type:    :boolean,
        default: false,
        desc:    "Run the real agent in a temp repository (spends tokens)"
      option :max_tokens,
        type: :integer,
        desc: "Token cap per live case (default #{Evals::Live::DEFAULT_MAX_TOKENS})"
      option :cases, desc: "Directory of <agent>/<id>.yml cases (default: the gem's evals/cases)"

      example [
        "                              # score every pass/ recording",
        "--recording fail              # the fail/ ones, which should all FAIL",
        "-a #{OpenLanes::Agents::Names::RESEARCHER} --depth deep",
        "--live -c research-fast --max-tokens 100000"
      ]

      # @param name [String, nil] the positional spelling of `--agent`
      # @param options [Hash]
      # @return [void]
      def call(name: nil, **options)
        options = options.merge(agent: name) if name && options[:agent].nil?
        quiet?(options)
        refuse("--max-tokens only applies to --live runs.", 64) if options[:max_tokens] && !options[:live]
        cases = selected(options)
        scores = options[:live] ? live(cases, options) : offline(cases, options.fetch(:recording, "pass"))
        $stdout.write(report(scores))
        exit 1 unless scores.all? { |s, _| s.passed? }
      end

      private

      # @return [Array<OpenLanes::Evals::Case>]
      def selected(options)
        all = Evals.cases(options[:cases] || Evals::DEFAULT_DIR)
        picked = all.select do |kase|
          (options[:agent].nil? || kase.agent == options[:agent]) && (options[:case].nil? || kase.id == options[:case])
        end
        refuse("No eval case matches #{filters(options)}.", 66) if picked.empty?
        picked.map { |kase| kase.at(options[:depth]) }
      rescue Evals::Invalid => e
        refuse(e.message, 65)
      end

      # @return [String]
      def filters(options) = options.slice(:agent, :case).map { |k, v| "--#{k} #{v}" }.join(" ").then { it.empty? ? "(none)" : it }

      # @return [Array<Array(OpenLanes::Evals::Score, OpenLanes::Evals::Run)>]
      def offline(cases, kind)
        cases.filter_map do |kase|
          recording = kase.recording(kind)
          unless recording
            UI.line("#{kase} has no #{kind}/ recording, skipped")
            next
          end
          [Evals.score_recording(kase, kind.to_sym), recording.run]
        end
      end

      # @return [Array<Array(OpenLanes::Evals::Score, OpenLanes::Evals::Run)>]
      def live(cases, options)
        credentials_warning
        cap = options[:max_tokens] || Evals::Live::DEFAULT_MAX_TOKENS
        cases.map do |kase|
          UI.line("running #{kase} at #{kase.depth}, capped at #{cap} tokens")
          outcome = Evals.run_live(kase, max_tokens: cap)
          result = outcome.result
          [outcome.score, Evals::Run.new(seconds: result.seconds, tokens: result.fresh)]
        end
      end

      # The table, then what failed and why: the deliverable, on STDOUT.
      #
      # @return [String]
      def report(scores)
        rows = scores.map do |score, run|
          kase = score.kase
          [kase.id, kase.agent, kase.depth, score.tally, run.seconds&.round || "-", run.tokens || "-",
           score.passed? ? "PASS" : "FAIL"]
        end
        table = UI.table(rows, header: %w[Case Agent Depth Checks Seconds Tokens Result])
        details = scores.reject { |s, _| s.passed? }.map do |score, _|
          lines = score.failures.map { |v| "  - #{v.name}: #{v.detail}" }
          lines = ["  - no checks apply at #{score.kase.depth}"] if lines.empty?
          "#{score.kase} FAIL\n#{lines.join("\n")}\n"
        end
        [table, *details].join("\n")
      end
    end
  end
end
