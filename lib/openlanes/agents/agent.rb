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
    # @!attribute [r] effort
    #   @return [String, nil] passed to `claude --effort`
    # @!attribute [r] starts_as
    #   @return [Symbol, nil] the state the harness renames the plan into the
    #     moment this agent is dispatched, where the topology permits it
    # @!attribute [r] holds_at
    #   @return [Symbol, nil] the state the plan takes when this agent completes
    #     while its partner on the same plan is still running
    # @!attribute [r] adapter
    #   @return [String] which coding agent runs it: `claude`, `codex` or `pi`
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
    Agent = Data.define(:name,
      :description,
      :handles,
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
      :toggle) do
      def initialize(ledger: [], rounds: 1, effort: nil, starts_as: nil, holds_at: nil, adapter: Adapters::DEFAULT,
        phase: nil, starts: [], needs: [], toggle: nil, **rest)
        super
      end

      # @return [Boolean] whether this agent changes anything on disk
      def read_only? = advances_to.nil?

      # @param status [OpenLanes::Plans::Status]
      # @return [Boolean]
      def handles?(status) = handles.include?(status.key)

      # @param value [Symbol] one of {Plans::Spec::STARTS}
      # @return [Boolean]
      def serves?(value) = starts.empty? || starts.include?(value.to_sym)

      # The word after the last hyphen: `researcher`, `backend`, and `planner`
      # for `luthen-rael-planner`, whose name has two words before its role.
      # What the screen's agent column shows, the name being too long for it.
      #
      # @return [String]
      def role = name.split("-").last.to_s
    end

    # More rounds than this costs tokens and buys nothing: an agent that has
    # not finished in five tries is not going to on the sixth.
    Agent::MAX_ROUNDS = 5
  end
end
