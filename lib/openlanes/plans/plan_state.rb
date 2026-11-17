# frozen_string_literal: true

require "forwardable"

module OpenLanes
  module Plans
    # `state.json` in a plan folder: what has happened to this plan, in a form
    # a program can read without parsing prose. Each kind of record is one
    # section under `plan_state/`, all built on one {Document}, which takes the
    # lock and writes atomically. This facade keeps every caller's method,
    # keyword and default; a value type (`Signature`, `Ruling`, …) carries the
    # defaults of a signature too long to spell out here.
    class PlanState
      extend Forwardable

      FILENAME = "state.json"
      # Bumped when a field changes meaning. Readers accept older versions.
      VERSION = 1
      SCHEMA_ID = "https://github.com/kigster/openlanes/blob/main/schemas/plan-state.schema.json"
      # A stage's status for a start that spent nothing; a ledger status, not a {Plans::Status}.
      FAILED_START = "Failed start"
      SCHEMA_PATH = File.expand_path("../../../schemas/plan-state.schema.json", __dir__)
      # How a plan finished: staff-reviewer approved it, or its pull request merged.
      FINISH_KINDS = %w[approved merged].freeze
      # Where the journals (M2), an agent's {Journal::Held}, and the resume records live.
      MEMORY = "memory"
      HELD = "held"
      LAST_KNOWN = "last-known-state"

      # @param dir [String] a plan folder
      # @return [OpenLanes::Plans::PlanState]
      def self.for(dir) = new(dir:)

      # @param dir [String] a plan folder
      def initialize(dir:)
        @document = Document.new(dir:)
        @stages, @recovery, @rulings, @lock, @finish, @signatures, @messages, @conversions =
          [Stages, Recovery, Rulings, LockRecord, Finish, Signatures, Messages, Conversions].map { it.new(@document) }
        @extensions, @quality, @risk, @memory, @holds, @answers, @last_known =
          [Extensions, QualityAsk, MergeRisk, Memory, Holds, Answers, LastKnown].map { it.new(@document) }
      end

      def_delegators :@document, :dir, :path, :exist?, :read, :update
      def_delegators :@stages, :stages, :state, :state!, :moves, :resume_until
      def_delegators :@rulings, :rulings
      def_delegators :@lock, :global_lock_taken_at, :release_global_lock!
      def_delegators :@finish, :finished, :unfinish!
      def_delegators :@signatures, :signatures, :ledger
      def_delegators :@messages, :messages
      def_delegators :@conversions, :conversions, :converted?
      def_delegators :@extensions, :extensions, :spend_extension!
      def_delegators :@quality, :quality_ask
      def_delegators :@risk, :merge_risk
      def_delegators :@memory, :journal
      def_delegators :@holds, :held, :forget_held!
      def_delegators :@answers, :blocked_by
      def_delegators :@last_known, :record_last_known, :last_known, :last_known_states

      def rule!(**) = @rulings.rule!(Ruling.new(**))
      def sign!(**) = @signatures.sign!(Signature.new(**))
      def message!(**) = @messages.message!(Message.new(**))
      def conversion!(**) = @conversions.conversion!(Conversion.new(**))
      def stage!(agent:, round:, reset: false, **fields) = @stages.stage!(agent, round, reset, fields)
      def resumption(agent:, state:, root:, adapter: nil) = @recovery.resumption(agent, state, root, adapter)
      def stranded(alive: Recovery.method(:alive?), pid: Process.pid) = @recovery.stranded(alive, pid)
      def resumed?(now: Time.now) = @stages.resumed?(now)
      def resume_anyway!(till:) = @stages.resume_anyway!(till)
      def take_global_lock!(at: Time.now) = @lock.take_global_lock!(at)
      def finish!(kind, at: Time.now) = @finish.finish!(kind, at)
      def deliver!(message, reserved: []) = @messages.deliver!(message, reserved)
      def ack!(number, by:) = @messages.ack!(number, by)
      def settle_extension!(number, at: Time.now, **fields) = @extensions.settle_extension!(number, at, fields)
      def amend_extension!(number, **fields) = @extensions.amend_extension!(number, fields)
      def ask_quality!(at: Time.now) = @quality.ask_quality!(at)
      def settle_quality_ask!(answer:, by:, at: Time.now) = @quality.settle_quality_ask!(answer, by, at)
      def assess!(verdicts, at: Time.now) = @risk.assess!(verdicts, at)
      def rebased!(number, at: Time.now) = @risk.rebased!(number, at)
      def hold!(agent:, session:) = @holds.hold!(agent, session)

      def ask_extension!(agent:, state:, round:, limit:, at: Time.now, **fields) # rubocop:disable Metrics/ParameterLists -- callers' keywords
        @extensions.ask_extension!(ExtensionAsk.new(agent:, state:, round:, limit:, at:), fields)
      end

      def journal!(agent:, entries:, number: nil, round: nil, state: nil) # rubocop:disable Metrics/ParameterLists -- callers' keywords
        @memory.journal!(agent, entries, number, { "round" => round, "state" => state&.to_s }.compact)
      end

      def estimate_extension!(agent:, seconds:, why: nil, at: Time.now)
        @extensions.estimate_extension!(agent, { "estimate" => Integer(seconds), "why" => why, "estimated_at" => at.iso8601 })
      end

      def answer!(agent:, ref:, question:, answer:)
        @answers.answer!(agent, Journal::Entry.new(kind: "question", text: question, ref:, answer:))
      end
    end
  end
end
