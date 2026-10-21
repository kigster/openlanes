# frozen_string_literal: true

module OpenLanes
  module Adapters
    # What every adapter answers. A subclass overrides {#argv}; the rest has a
    # default that is right for a CLI with no opinions of its own.
    class Base
      # @return [String] the name agent frontmatter uses
      def name = self.class.name.split("::").last.downcase

      # @return [String] the executable, for messages
      def executable = name

      # @param invocation [OpenLanes::Adapters::Invocation]
      # @return [Array<String>]
      def argv(invocation) = raise NotImplementedError, "#{self.class} must build an argv for #{invocation.class}"

      # A parser for what this CLI prints, with the same interface as
      # {OpenLanes::Execution::Transcript}.
      #
      # @param trace [String, nil] where to keep every line verbatim
      # @return [#push, #finish, #up, #down, #failed?]
      def transcript(trace: nil, &) = Stream.new(trace:, &)

      # The model to ask for, after any ceiling this CLI imposes.
      #
      # @param model [String, nil]
      # @return [String, nil]
      def model(model) = model

      # @param effort [String, nil] one of {EFFORTS}
      # @return [String, nil] this CLI's word for it
      def effort(effort) = effort

      # What the child process gets on top of the harness's own environment.
      #
      # @return [Hash{String => String}]
      def environment = {}

      # The models this CLI offers, most capable first, for the page's
      # dropdowns and the cost meter. Empty for a CLI nobody has priced.
      #
      # @return [Array<OpenLanes::Adapters::Model>]
      def models = []

      # @param name [String, nil] an alias or a full id
      # @return [OpenLanes::Adapters::Model, nil]
      def model_entry(name) = models.find { |m| m.id == name.to_s }

      # What this CLI can do. Abstract on purpose: every adapter declares all
      # of it, and the Executor and Dispatcher branch on these, never on
      # {#name}.
      #
      # @return [OpenLanes::Adapters::Capabilities]
      def capabilities = raise NotImplementedError, "#{self.class} must declare its capabilities"

      # The flags that start this CLI without the operator's personal
      # plugins, skills, hooks and MCP servers; empty where {#argv} builds
      # them itself.
      #
      # @return [Array<String>]
      def lean_flags = []

      # What, sent into a resumed session, makes this CLI compact it (W28);
      # nil for a CLI that cannot resume one, whose agents are therefore never
      # compacted mid-round.
      #
      # @return [String, nil]
      def compact_prompt = capabilities.compact_prompt

      # @return [Boolean] whether an agent on this CLI can be compacted and
      #   carried on in the same session
      def compacts? = capabilities.compacts

      # Whether {#argv} honours {Invocation#resume}. The copilot (W17) keeps
      # one conversation across messages only on a CLI that says yes; on any
      # other each message starts afresh, and says so.
      #
      # @return [Boolean]
      def resumes? = capabilities.resumes

      # Whether the CLI itself refuses the denied tools, rather than only being
      # asked not to use them. The prompt says which, because telling an agent
      # a guard exists when it does not is how it stops being careful.
      #
      # @return [Boolean]
      def enforces_tool_denial? = capabilities.enforces_tool_denial
    end
  end
end
