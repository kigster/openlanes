# frozen_string_literal: true

module OpenLanes
  module Engine
    # The engine step that runs `obi-wan-kenobi-arbitrator` (M7, M8, M9).
    # It is a side call, not a plan state: the agent is read-only, so the
    # registry never routes a state to it, and every ruling lands the plan
    # in a state that already exists.
    #
    # Once a tick, before agents are assigned, {#tick} asks each plan for a
    # trigger, in the spec's order, runs the arbitrator on the first plan
    # that has one, parses its `ruling` block and hands the result to
    # {OpenLanes::Arbitration::Effects}. At most one arbitration per plan
    # per tick, and {#holds?} keeps a capped plan from its builders.
    class Arbitration
      # Builders whose signatures may carry an appeal, and who may raise a dispute.
      BUILDERS = %w[luke-backend rey-frontend].freeze

      # A dispute is mail to the arbitrator whose body opens with this word.
      DISPUTE = /\Adispute:/i

      # What one arbitration came to.
      #
      # @!attribute [r] trigger
      #   @return [String]
      # @!attribute [r] effects
      #   @return [OpenLanes::Arbitration::Effects::Result, nil] nil when the answer could not be read
      # @!attribute [r] error
      #   @return [String, nil] why it could not
      Outcome = Data.define(:trigger, :effects, :error)

      # @param tree_dir [String] the `.plans` directory
      # @param agents [OpenLanes::Agents::Registry]
      # @param github [OpenLanes::Vcs::GitHub]
      # @param ask [#call] given the agent, the plan and the trigger text,
      #   returns the agent's final answer; the default runs it through
      #   {Execution.executor} and reads the answer from its trace
      # @param max_rejections [#call] `merge.max_rejections`
      # @param quality [#call] `desired_codebase_quality`; only `mvp` checks a
      #   `review-ok-not-perfect` verdict (M9: `medium` was dropped with R4)
      # @param effects [OpenLanes::Arbitration::Effects]
      def initialize(tree_dir:, agents:, github:, ask: nil, root: nil,
        max_rejections: -> { Config.current.max_rejections },
        quality: -> { Config.current.desired_codebase_quality },
        effects: OpenLanes::Arbitration::Effects.new(tree_dir:, github:))
        @tree_dir = tree_dir
        @agents = agents
        @github = github
        @ask = ask || Asker.new(root: root || File.dirname(tree_dir))
        @max = max_rejections
        @quality = quality
        @effects = effects
      end

      # Called by {Verification::Outcome} as a rejection reaches the cap.
      # The ruling itself runs on the next tick, where every trigger is
      # asked in one place.
      #
      # @param plan [OpenLanes::Plans::Subject]
      # @param count [Integer]
      # @param max [Integer]
      # @return [void]
      def call(plan:, count:, max:) = self.class.call(plan:, count:, max:)

      # The same notice, for a {Verification::Outcome} built without a run
      # to arbitrate in.
      #
      # @param plan [OpenLanes::Plans::Subject]
      # @param count [Integer]
      # @param max [Integer]
      # @return [void]
      def self.call(plan:, count:, max:)
        UI.log("rejected #{count} of #{max}: at the cap, the arbitrator rules next", level: :warn, plan: plan.feature.ordinal.to_s)
      end

      # @param subjects [Array<OpenLanes::Plans::Subject>] plans no agent is running on
      # @return [Array<Outcome>] one per plan arbitrated
      def tick(subjects)
        subjects.filter_map do |subject|
          found = triggered(subject) or next
          arbitrate(subject, found)
        end
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Hash, nil] `{ trigger:, appellant:, message: }`, the first
      #   that fires in the spec's order, nil when none does
      def triggered(subject)
        state = Plans::PlanState.for(subject.feature.path)
        appeal(state) || dispute(state) || cap(subject) || passed_check(subject, state)
      end

      # A plan at 🔴 whose rejections reached the cap belongs to the
      # arbitrator, not to luke and rey.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def holds?(subject) = !cap(subject).nil?

      private

      # @return [Outcome]
      def arbitrate(subject, found)
        agent = @agents.find(OpenLanes::Arbitration::AGENT)
        state = Plans::PlanState.for(subject.feature.path)
        round = state.rulings.size + 1
        state.stage!(agent: agent.name, round:, status: "Started", started_at: Time.now.iso8601)
        text = @ask.call(agent, subject, brief(subject, found))
        ruling = OpenLanes::Arbitration.ruling(text)
        result = @effects.apply(plan: subject, ruling:, trigger: found[:trigger], round:, appellant: found[:appellant])
        # The ruling may have renamed the folder: read it again where it is now.
        state = Plans::PlanState.for(Plans::Tree.new(dir: @tree_dir).find(subject.feature.ordinal.to_s).feature.path)
        state.ack!(found[:message], by: agent.name) if found[:message]
        state.stage!(agent: agent.name, round:, status: "Completed", note: ruling.headline, finished_at: Time.now.iso8601)
        Outcome.new(trigger: found[:trigger], effects: result, error: nil)
      rescue Error => e
        state&.stage!(agent: agent.name, round:, status: "Interrupted", note: e.message, finished_at: Time.now.iso8601)
        UI.log("arbitration refused: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
        Outcome.new(trigger: found[:trigger], effects: nil, error: e.message)
      end

      # @return [Hash, nil] the latest builder appeal no appeal ruling followed
      def appeal(state)
        last = state.rulings.select { it["kind"] == "appeal" }.map { Time.iso8601(it["at"]) }.max
        signature = state.signatures.rfind do |s|
          BUILDERS.include?(s["agent"]) && OpenLanes::Arbitration::Appeal.parse(s["note"]) && (last.nil? || Time.iso8601(s["at"]) > last)
        end
        signature && { trigger: "appeal", appellant: signature["agent"], note: signature["note"] }
      end

      # @return [Hash, nil] the oldest unread dispute mailed to the arbitrator
      def dispute(state)
        message = state.messages.find do |m|
          m["to"] == OpenLanes::Arbitration::AGENT && m["read"] != "yes" && m["body"].to_s.strip.match?(DISPUTE)
        end
        message && { trigger: "dispute", message: message["number"], note: message["body"], appellant: message["from"] }
      end

      # @return [Hash, nil]
      def cap(subject)
        return nil unless subject.status.key == :rejected

        count = OpenLanes::Arbitration.counter(agents: @agents).call(subject)
        max = @max.call
        count >= max ? { trigger: "cap", note: "rejected #{count} of #{max}" } : nil
      end

      # At `mvp` only: a `review-ok-not-perfect` pull request with no
      # `passed_check` ruling since hansolo's latest signature. Keyed by that
      # signature rather than the head SHA, so a re-poll never re-runs it and
      # a new review, after a new push, does.
      #
      # @return [Hash, nil]
      def passed_check(subject, state)
        return nil unless @quality.call == :mvp && %i[in_review ready_for_review].include?(subject.status.key)

        pull = subject.pull_requests.last or return nil
        reviewed = state.signatures.select { it["agent"] == "hansolo-reviewer" && it["status"] == "Completed" }.map { Time.iso8601(it["at"]) }.max
        return nil unless reviewed
        return nil if state.rulings.any? { it["kind"] == "passed_check" && Time.iso8601(it["at"]) > reviewed }

        labels = @github.labels(number: Vcs::GitHub.number_of(pull.url || pull.number), repo: Vcs::GitHub.repo_of(pull.url))
        labels.include?(Plans::ReviewLabel::OK_NOT_PERFECT.name) ? { trigger: "passed_check", note: "review-ok-not-perfect at mvp" } : nil
      rescue Error
        nil
      end

      # What the arbitrator is told on top of its definition.
      #
      # @return [String]
      def brief(subject, found)
        pull = subject.pull_requests.last
        ["Trigger: #{found[:trigger]}", ("Pull request: #{pull.url || pull.number}" if pull),
         ("Raised by: #{found[:appellant]}" if found[:appellant]), ("Says: #{found[:note]}" if found[:note]),
         "Plan folder: #{subject.feature.path}"].compact.join("\n")
      end

      # Runs the arbitrator through the executor in the main checkout (it
      # writes nothing, so it needs no worktree of its own), then reads its
      # final answer back from the trace the executor wrote.
      class Asker
        # @param root [String]
        # @param executor [#call] builds the executor, given `root:` and `instructions:`
        # @param trace_dir [String] where the executor writes its traces
        def initialize(root:, executor: ->(**kw) { Execution.executor(**kw) }, trace_dir: Execution::Executor::TRACE_DIR)
          @root = root
          @executor = executor
          @trace_dir = trace_dir
        end

        # @return [String] the agent's final answer, empty when none was read
        def call(agent, subject, brief)
          since = Time.now
          @executor.call(root: @root, instructions: brief, trace_dir: @trace_dir).call(agent, subject)
          trace = Dir[File.join(@trace_dir, "*-#{subject.feature.ordinal}-#{agent.name}-*.ndjson")]
                  .select { File.mtime(it) >= since - 1 }.max_by { File.mtime(it) }
          return "" unless trace

          File.foreach(trace).filter_map { JSON.parse(it)["result"] if it.include?("\"result\"") }.last.to_s
        rescue JSON::ParserError
          ""
        end
      end
    end
  end
end
