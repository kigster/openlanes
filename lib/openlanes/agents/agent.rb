# frozen_string_literal: true

module OpenLanes
  module Agents
    # One specialist, loaded from `~/.agents/agents/<name>.md`.
    #
    # The definition files are the single source of truth for who does what: the
    # frontmatter says which plan states this agent handles and what it may write,
    # and the body is the prompt. Nothing about a specialty is duplicated in Ruby.
    #
    # @!attribute [r] name
    #   @return [String]
    # @!attribute [r] description
    #   @return [String]
    # @!attribute [r] handles
    #   @return [Array<Symbol>] plan states this agent is offered work from
    # @!attribute [r] covers
    #   @return [Array<Symbol>] plan states it is offered only when no agent
    #     that handles them would be given the plan
    # @!attribute [r] advances_to
    #   @return [Symbol, nil] the state it is expected to reach; nil = read-only
    # @!attribute [r] model
    #   @return [String, nil]
    # @!attribute [r] allowed_tools
    #   @return [Array<String>]
    # @!attribute [r] may
    #   @return [Array<String>] commands lifted from {Executor::FORBIDDEN_COMMANDS}
    #     for this agent alone. Nothing in {Executor::UNGRANTABLE} can be lifted.
    # @!attribute [r] timeout
    #   @return [Integer, nil] seconds before this agent is abandoned; nil
    #     defers to the executor's run-wide default
    # @!attribute [r] ledger
    #   @return [Array<String>] the documents this agent signs, in the order
    #     it reaches them; the last entry it wrote is where it stands
    # @!attribute [r] rounds
    #   @return [Integer] how many times it may be invoked on one plan in one
    #     state before the plan parks; a Completed never earns another
    # @!attribute [r] review_stage
    #   @return [Integer] which pass of a review round a reviewer belongs to:
    #     1 reads the pull request first, and 2 only once every 1 has passed
    #     it and CI is green ({Engine::Reviews#due?})
    # @!attribute [r] effort
    #   @return [String, nil] passed to `claude --effort`
    # @!attribute [r] starts_as
    #   @return [Symbol, nil] the state the harness renames the plan into the
    #     moment this agent is dispatched, where the topology permits it
    # @!attribute [r] holds_at
    #   @return [Symbol, nil] the state the plan takes when this agent completes
    #     while its partner on the same plan is still running
    # @!attribute [r] adapter
    #   @return [String] which coding agent runs it: `claude`, `codex`, `pi`, `grok` or `gemini`
    # @!attribute [r] phase
    #   @return [String, nil] the word a spec's `phases:` map uses to reach it
    # @!attribute [r] starts
    #   @return [Array<Symbol>] which {Plans::Spec::STARTS} values this agent
    #     works on; empty means every one
    # @!attribute [r] needs
    #   @return [Array<String>] plan files that must hold at least one work-unit
    #     heading before it is dispatched
    # @!attribute [r] toggle
    #   @return [String, nil] a spec.md frontmatter key that switches it off
    #     when false and on when true
    # @!attribute [r] confined_to
    #   @return [Array<String>] the plan files, relative to its folder, that
    #     are all it may edit; empty means it is not confined. Enforced by
    #     {Execution::Executor}, not asked for in the prompt.
    # @!attribute [r] small_diff
    #   @return [OpenLanes::Agents::SmallDiff, nil] the model it runs on for a
    #     small diff; nil when it has none
    Agent = Data.define(:name,
      :description,
      :handles,
      :covers,
      :advances_to,
      :model,
      :allowed_tools,
      :may,
      :network,
      :timeout,
      :prompt,
      :path,
      :ledger,
      :rounds,
      :effort,
      :starts_as,
      :holds_at,
      :adapter,
      :phase,
      :starts,
      :needs,
      :toggle,
      :confined_to,
      :small_diff,
      :review_stage) do
      def initialize(covers: [], ledger: [], rounds: Agent::DEFAULT_ROUNDS, effort: nil, starts_as: nil, holds_at: nil, adapter: nil,
        phase: nil, starts: [], needs: [], toggle: nil, confined_to: [], small_diff: nil, review_stage: 1, **rest)
        super
      end

      # @return [Boolean] whether this agent changes anything on disk
      def read_only? = advances_to.nil?

      # @return [Boolean] whether {#confined_to} limits what it may edit
      def confined? = !confined_to.empty?

      # @param status [OpenLanes::Plans::Status]
      # @return [Boolean]
      def handles?(status) = handles.include?(status.key)

      # @param status [OpenLanes::Plans::Status]
      # @return [Boolean]
      def covers?(status) = covers.include?(status.key)

      # @param value [Symbol] one of {Plans::Spec::STARTS}
      # @return [Boolean]
      def serves?(value) = starts.empty? || starts.include?(value.to_sym)

      # The word after the last hyphen: `researcher`, `backend`, and `planner`
      # for `planner`, whose name has two words before its role.
      # What the screen's agent column shows, the name being too long for it.
      #
      # @return [String]
      def role = name.split("-").last.to_s
    end

    # More rounds than this costs tokens and buys nothing: an agent that has
    # not finished in five tries is not going to on the sixth.
    Agent::MAX_ROUNDS = 5

    # The rounds an agent gets when its definition names none. It was one,
    # and nearly every agent then stopped at "no rounds left" with the work
    # half done and waited for a person to grant one more, over and over.
    Agent::DEFAULT_ROUNDS = 4
  end
end
