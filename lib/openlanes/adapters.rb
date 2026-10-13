# frozen_string_literal: true

module OpenLanes
  # The coding agents a plan can be handed to: `claude`, `codex` and `pi`.
  #
  # The harness decides who works which plan and checks what they did; an
  # adapter only knows how to start one particular CLI and how to read what
  # it prints. That is the whole seam, and it is what lets an agent
  # definition say `adapter: codex` without the run loop noticing.
  module Adapters
    # Reasoning effort, in the vocabulary agent frontmatter and spec.md use.
    # Each adapter translates it into its own CLI's words.
    EFFORTS = %w[low medium high xhigh max].freeze

    # Percent of the context window at which every agent compacts itself
    # (W28), instead of the CLI's default near the limit: a long session's
    # quality drops well before its window is full. Each adapter maps it to
    # its own CLI's setting in {Base#environment}.
    AUTOCOMPACT = 40

    # Everything an adapter needs to start one agent, and nothing about why.
    #
    # @!attribute [r] prompt
    #   @return [String]
    # @!attribute [r] root
    #   @return [String] the checkout the agent works in
    # @!attribute [r] model
    #   @return [String, nil] nil lets the CLI choose
    # @!attribute [r] effort
    #   @return [String, nil] one of {EFFORTS}
    # @!attribute [r] allowed_tools
    #   @return [Array<String>]
    # @!attribute [r] denied_tools
    #   @return [Array<String>] tool names, plus `Bash(<command>:*)` specifiers
    # @!attribute [r] denied_commands
    #   @return [Array<String>] the bare commands behind those specifiers
    # @!attribute [r] network
    #   @return [Boolean] whether the agent may reach the internet
    # @!attribute [r] lean
    #   @return [Boolean] start without the operator's personal plugins,
    #     skills, hooks and MCP servers
    # @!attribute [r] resume
    #   @return [String, nil] a session to carry on rather than start afresh
    # @!attribute [r] slash_commands
    #   @return [Boolean] keep the CLI's slash commands even when lean, which
    #     only the `/compact` sent into a resumed session needs
    # @!attribute [r] dirs
    #   @return [Array<String>] directories beyond {#root} the agent may read,
    #     such as the trace directory the copilot reads transcripts from
    # @!attribute [r] brief
    #   @return [Boolean] whether the agent reports through the CLI's
    #     one-line status tool, which only a car on the board has a use for
    # @!attribute [r] tools
    #   @return [Array<String>, nil] the only built-in tools the agent has, with
    #     no settings file able to add one; nil leaves the CLI's own set
    # @!attribute [r] system
    #   @return [String, nil] standing instructions, sent as system prompt on
    #     every invocation so a compacted conversation does not lose them
    Invocation = Data.define(:prompt,
      :root,
      :model,
      :effort,
      :allowed_tools,
      :denied_tools,
      :denied_commands,
      :network,
      :lean,
      :resume,
      :slash_commands,
      :dirs,
      :brief,
      :tools,
      :system) do
      def initialize(allowed_tools: [], denied_tools: [], denied_commands: [], network: false, lean: true,
        model: nil, effort: nil, resume: nil, slash_commands: false, dirs: [], brief: true, tools: nil, system: nil,
        **rest)
        super
      end
    end

    # The adapter every agent gets unless its definition names another.
    DEFAULT = "claude"

    module_function

    # @return [Hash{String => Class}]
    def registry = { "claude" => Claude, "codex" => Codex, "pi" => Pi }

    # @return [Array<String>]
    def names = registry.keys

    # @param name [String, Symbol, nil]
    # @return [OpenLanes::Adapters::Base]
    # @raise [OpenLanes::Error] for a name nothing answers to
    def for(name)
      key = (name || DEFAULT).to_s
      klass = registry[key] or raise OpenLanes::Error, "unknown adapter #{key.inspect}; known: #{names.join(", ")}"
      klass.new
    end

    # @param name [String, Symbol, nil]
    # @return [Boolean]
    def known?(name) = registry.key?((name || DEFAULT).to_s)

    # @param level [String, Symbol, nil]
    # @return [Boolean]
    def effort?(level) = EFFORTS.include?(level.to_s)
  end
end
