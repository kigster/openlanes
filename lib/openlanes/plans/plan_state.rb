# frozen_string_literal: true

require "forwardable"
# What loading the class loaded before the split, where every section's code
# lived in this one file. Code that never requires these itself came to rely
# on it ({Rounds} parsed times with only `PlanState` having loaded `time`), so
# the split keeps the load order it found.
%w[digest fileutils json securerandom socket time tmpdir].each { require it }

module OpenLanes
  module Plans
    # `state.json` in a plan folder: what has happened to this plan, in a form
    # a program can read without parsing prose. Each kind of record is one
    # section under `plan_state/`, all built on one {Document}, which takes the
    # lock and writes atomically.
    #
    # This facade is the contract callers see. Readers, and writers that take
    # one plain argument, go straight to their section and are documented
    # there. Every other writer is spelled out below with the keywords and
    # defaults callers have always passed, so Ruby still refuses a keyword
    # nobody declared: forwarding `**` let `sign!(..., "note" => "x")` write a
    # signature without its note instead of raising.
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

      # Each section by the name the facade reads it under, beside the class
      # that serves it. Two parallel arrays held these once, assigned by
      # position, and swapping two names there would have put the wrong
      # section behind a method without a word.
      SECTIONS = {
        stages: Stages, recovery: Recovery, rulings: Rulings, lock: LockRecord, finish: Finish,
        signatures: Signatures, messages: Messages, conversions: Conversions, extensions: Extensions,
        quality: QualityAsk, risk: MergeRisk, memory: Memory, holds: Holds, answers: Answers, last_known: LastKnown
      }.freeze

      # @param dir [String] a plan folder
      # @return [OpenLanes::Plans::PlanState]
      def self.for(dir) = new(dir:)

      # @param dir [String] a plan folder
      def initialize(dir:)
        @document = Document.new(dir:)
        @sections = SECTIONS.transform_values { it.new(@document) }.freeze
      end

      def_delegators :@document, :dir, :path, :exist?, :read, :update
      def_delegators "section(:stages)", :stages, :state, :state!, :moves, :resume_until
      def_delegators "section(:rulings)", :rulings
      def_delegators "section(:lock)", :global_lock_taken_at, :release_global_lock!
      def_delegators "section(:finish)", :finished, :unfinish!
      def_delegators "section(:signatures)", :signatures, :ledger
      def_delegators "section(:messages)", :messages
      def_delegators "section(:conversions)", :conversions, :converted?
      def_delegators "section(:extensions)", :extensions, :spend_extension!
      def_delegators "section(:quality)", :quality_ask
      def_delegators "section(:risk)", :merge_risk
      def_delegators "section(:memory)", :journal
      def_delegators "section(:holds)", :held, :forget_held!
      def_delegators "section(:answers)", :blocked_by
      def_delegators "section(:last_known)", :record_last_known, :last_known, :last_known_states

      # Record one ruling, written by the engine from the arbitrator's block
      # (M7: the agent itself writes nothing).
      #
      # @param kind [String] cap, appeal, dispute or passed_check
      # @param pr [Integer, nil]
      # @param round [Integer, nil]
      # @param outcome [String]
      # @param findings [Hash] `{ "struck" => [...], "critical" => [...] }`,
      #   with `"headings"` mapping a struck id to its heading when known
      # @param winner [String, nil] dispute only
      # @param reason [String]
      # @param trigger [String] what started the arbitration
      # @param review [Integer, nil] the round of staff-reviewer's review the
      #   struck ids belong to: staff-reviewer numbers from F1 in every review
      # @param at [Time]
      # @return [Hash] the ruling as written
      # @see Rulings#rule!
      def rule!(kind:, pr:, round:, outcome:, findings:, winner:, reason:, trigger:, review: nil, at: Time.now) # rubocop:disable Naming/MethodParameterName, Metrics/ParameterLists -- the ruling block's own keys
        ruling = Ruling.new(kind:, pr:, round:, outcome:, findings:, winner:, reason:, trigger:, review:, at:)
        section(:rulings).rule!(ruling)
      end

      # One ledger line, in JSON. What `openlanes state sign` writes.
      #
      # @param agent [String]
      # @param round [Integer]
      # @param status [String] one of {Ledger::STATUSES}
      # @param note [String, nil]
      # @param next_agent [String, nil] only after Completed
      # @param at [Time]
      # @return [Hash] the signature as written
      # @raise [OpenLanes::Error] for a status outside the ledger's vocabulary,
      #   a handoff after anything but Completed, or an agent that is not one token
      # @see Signatures#sign!
      def sign!(agent:, round:, status:, note: nil, next_agent: nil, at: Time.now) # rubocop:disable Metrics/ParameterLists -- callers' keywords
        section(:signatures).sign!(Signature.new(agent:, round:, status:, note:, next_agent:, at:))
      end

      # Append one message and give it the next number.
      #
      # @param from [String]
      # @param to [String]
      # @param body [String]
      # @param at [Time]
      # @param after [Integer] numbers already taken elsewhere, so a plan
      #   whose older messages are in mailbox.md keeps counting from there
      # @param command [String, nil] the id of the page's command that sent it (W13)
      # @return [Hash] the message as written, or the one an earlier append
      #   under the same +command+ wrote
      # @see Messages#message!
      def message!(from:, to:, body:, at: Time.now, after: 0, command: nil) # rubocop:disable Metrics/ParameterLists -- callers' keywords
        section(:messages).message!(Message.new(from:, to:, body:, at:, after:, command:))
      end

      # A question the engine rewrote into lettered choices (D9), or tried to.
      #
      # @param question [Integer] the `n` of `## Bn`
      # @param digest [String] SHA256 of +original+
      # @param original [String] the body before the rewrite
      # @param model [String] the model asked
      # @param outcome [String] "converted" or "rejected"
      # @param note [String, nil] why it was rejected
      # @param at [Time]
      # @return [Hash] the record as written
      # @see Conversions#conversion!
      def conversion!(question:, digest:, original:, model:, outcome:, note: nil, at: Time.now) # rubocop:disable Metrics/ParameterLists -- callers' keywords
        section(:conversions).conversion!(Conversion.new(question:, digest:, original:, model:, outcome:, note:, at:))
      end

      # Record or update one agent's round.
      #
      # @param agent [String]
      # @param round [Integer]
      # @param reset [Boolean] start a new record rather than update one
      # @param fields [Hash] status, started_at, finished_at, adapter, model,
      #   effort, up, down, seconds, note, from, state, to, session, cwd,
      #   handed_back; `run` only in files older releases wrote
      # @return [Hash] the stage as written
      # @see Stages#stage!
      def stage!(agent:, round:, reset: false, **fields) = section(:stages).stage!(agent, round, reset, fields)

      # Whether one agent's next round may carry on the session its last one
      # ran in (M1), and if not, why not.
      #
      # @param agent [String]
      # @param state [#to_s] the state key the plan is in now
      # @param root [String] the checkout the new round will run in
      # @param adapter [#to_s, nil] the adapter the new round runs on
      # @return [OpenLanes::Plans::PlanState::Resumption]
      # @see Recovery#resumption
      def resumption(agent:, state:, root:, adapter: nil) = section(:recovery).resumption(agent, state, root, adapter)

      # @param alive [#call] pid → Boolean
      # @param pid [Integer] this run, which is never its own crash
      # @return [Array<Hash>] the stages a dead harness left Started
      # @see Recovery#stranded
      def stranded(alive: Recovery.method(:alive?), pid: Process.pid) = section(:recovery).stranded(alive, pid)

      # @param now [Time]
      # @return [Boolean] whether a halt on this plan is lifted right now
      def resumed?(now: Time.now) = section(:stages).resumed?(now)

      # "Resume anyway for 24 h" from the control room.
      #
      # @param till [Time] when the halt comes back
      # @return [Time] as written
      def resume_anyway!(till:) = section(:stages).resume_anyway!(till)

      # @param at [Time]
      # @return [Time] the time kept: the first one, when the lock was taken already
      # @see LockRecord#take_global_lock!
      def take_global_lock!(at: Time.now) = section(:lock).take_global_lock!(at)

      # @param kind [String] one of {FINISH_KINDS}
      # @param at [Time]
      # @return [OpenLanes::Plans::PlanState::Finished] the record kept
      # @raise [OpenLanes::Error] for a kind outside {FINISH_KINDS}
      # @see Finish#finish!
      def finish!(kind, at: Time.now) = section(:finish).finish!(kind, at)

      # @param message [Hash] as {#message!} writes it, string keys
      # @param reserved [Array<Integer>] numbers taken outside this file, i.e. by mailbox.md
      # @return [Hash, nil] the message as written, nil when it was here
      # @see Messages#deliver!
      def deliver!(message, reserved: []) = section(:messages).deliver!(message, reserved)

      # @param number [Integer]
      # @param by [String] the agent acking, who must be the recipient
      # @return [Hash, nil] the message as written, nil when there is no such number
      # @raise [OpenLanes::Error] when +by+ is not the recipient
      # @see Messages#ack!
      def ack!(number, by:) = section(:messages).ack!(number, by)

      # @param number [Integer]
      # @param at [Time]
      # @param fields [Hash] `answer`, `by`, `grant`, `seconds`, `closed`
      # @return [Hash, nil] the request as settled; nil when there is no such
      #   request, or when it was settled already
      # @see Extensions#settle_extension!
      def settle_extension!(number, at: Time.now, **fields) = section(:extensions).settle_extension!(number, at, fields)

      # @param number [Integer]
      # @param fields [Hash] how the grant was actually given
      # @return [Hash, nil] the request as it now stands
      # @see Extensions#amend_extension!
      def amend_extension!(number, **fields) = section(:extensions).amend_extension!(number, fields)

      # @param at [Time]
      # @return [Hash] R4's ask as it stands; asking twice keeps the first moment
      # @see QualityAsk#ask_quality!
      def ask_quality!(at: Time.now) = section(:quality).ask_quality!(at)

      # @param answer [String] "high", "standard" or "mvp"
      # @param by [String]
      # @param at [Time]
      # @return [Hash, nil] the ask as settled; nil when none is open
      def settle_quality_ask!(answer:, by:, at: Time.now) = section(:quality).settle_quality_ask!(answer, by, at)

      # @param verdicts [Hash{Integer, String => String}] pull request number => its risk,
      #   one of {Engine::Merging::RISKS}, or `unassessed`
      # @param at [Time]
      # @return [Hash] the record kept
      # @see MergeRisk#assess!
      def assess!(verdicts, at: Time.now) = section(:risk).assess!(verdicts, at)

      # @param number [Integer] the sibling pull request the engine rebased
      # @param at [Time]
      # @return [void]
      def rebased!(number, at: Time.now) = section(:risk).rebased!(number, at)

      # @param agent [String]
      # @param session [String] the CLI's session id
      # @return [OpenLanes::Plans::Journal::Held]
      # @see Holds#hold!
      def hold!(agent:, session:) = section(:holds).hold!(agent, session)

      # The harness asking a person for more time or another round (E1).
      #
      # @param agent [String]
      # @param state [String] the plan state the agent was working, a {Status} key
      # @param round [Integer]
      # @param limit [String] "time" or "rounds", whichever ran out
      # @param at [Time]
      # @param fields [Hash] `stage`; the `by`, `grant`, `seconds` and
      #   `settled_at` of a grant made outright; or `cause`, why it is asked
      #   when nothing ran out
      # @return [Hash] the request as written, with its `number`
      # @see Extensions#ask_extension!
      def ask_extension!(agent:, state:, round:, limit:, at: Time.now, **fields) # rubocop:disable Metrics/ParameterLists -- callers' keywords
        section(:extensions).ask_extension!(ExtensionAsk.new(agent:, state:, round:, limit:, at:), fields)
      end

      # Append entries to one of the agent's journal rounds, as they arrive.
      #
      # @param agent [String]
      # @param entries [Array<OpenLanes::Plans::Journal::Entry>]
      # @param number [Integer, nil] the journal round, nil to start one
      # @param round [Integer, nil] the dispatcher's round, kept beside it
      # @param state [#to_s, nil] the state the round started in
      # @return [Array(Integer, Array<OpenLanes::Plans::Journal::Rejection>)]
      #   the journal round written to, and what was refused
      # @raise [OpenLanes::Error] on an agent name that is not one token
      # @see Memory#journal!
      def journal!(agent:, entries:, number: nil, round: nil, state: nil) # rubocop:disable Metrics/ParameterLists -- callers' keywords
        section(:memory).journal!(agent, entries, number, Memory.opening(round, state))
      end

      # The agent's own answer to "how much more time do you need" (E2).
      #
      # @param agent [String]
      # @param seconds [Integer]
      # @param why [String, nil]
      # @param at [Time]
      # @return [Hash, nil] the request as it now stands; nil when nobody is
      #   waiting on this agent's estimate
      # @see Extensions#estimate_extension!
      def estimate_extension!(agent:, seconds:, why: nil, at: Time.now)
        section(:extensions).estimate_extension!(agent, seconds, why, at)
      end

      # A person's answer to one of the agent's `blocked.md` questions (M3).
      #
      # @param agent [String]
      # @param ref [String] `B<n>`
      # @param question [String]
      # @param answer [String]
      # @return [OpenLanes::Plans::Journal::Entry, nil] nil when it was there
      # @raise [OpenLanes::Error] on an agent name that is not one token
      # @see Answers#answer!
      def answer!(agent:, ref:, question:, answer:)
        section(:answers).answer!(agent, Journal::Entry.new(kind: "question", text: question, ref:, answer:))
      end

      private

      # @param name [Symbol] a key of {SECTIONS}
      # @return [OpenLanes::Plans::PlanState::Section]
      # @raise [KeyError] for a name no section has
      def section(name) = @sections.fetch(name)
    end
  end
end
