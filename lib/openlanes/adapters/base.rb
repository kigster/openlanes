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

      # The command that puts one question to this CLI and prints the answer as
      # plain text, in the mode that can change nothing. For a question that
      # needs a model and no work done, so it never takes {#argv}'s write access.
      # Abstract, like {#capabilities}: each CLI locks itself down its own way.
      #
      # @param prompt [String]
      # @param model [String, nil] nil lets the CLI choose
      # @return [Array<String>]
      def question_argv(prompt, model: nil) = raise NotImplementedError, "#{self.class} must build a read-only argv for #{prompt.class}, #{model.class}"

      # A parser for what this CLI prints, with the same interface as
      # {OpenLanes::Execution::Transcript}.
      #
      # @param trace [String, nil] where to keep every line verbatim
      # @param argv [Array<String>] the command whose output it reads, for a
      #   CLI that names its session there rather than in its stream
      # @return [#push, #finish, #up, #down, #failed?]
      def transcript(trace: nil, **, &) = Stream.new(trace:, &)

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

      # Whether this CLI can take an agent here and now (D5): installed,
      # signed in, with a model to run. Local commands only, never a prompt.
      #
      # @param runner [OpenLanes::Adapters::ProbeRunner]
      # @param at [Time] when the probe ran
      # @return [OpenLanes::Adapters::Availability]
      def probe(runner: Adapters.probe_runner, at: Time.now)
        return Availability.down(name, "not installed (no `#{executable}` on PATH)", at) unless runner.which(executable)

        check(runner, at)
      end

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

      # Whether a {Agents::Agent#confined? confined} agent can run on this
      # CLI at all: one that cannot hold it to its files is refused it.
      #
      # @return [Boolean]
      def confines? = capabilities.confines

      private

      # The installed CLI's own answer to {#probe}. Abstract, like
      # {#capabilities}: each CLI says "signed in" differently.
      #
      # @param runner [OpenLanes::Adapters::ProbeRunner]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def check(runner, at) = raise NotImplementedError, "#{self.class} must probe itself (#{runner.class}, #{at})"

      # A command that never finished, said once for every adapter.
      #
      # @param result [OpenLanes::Adapters::ProbeRunner::Result]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def timed_out(result, at) = Availability.down(name, "`#{executable}` did not answer: #{result.stderr}", at)
    end
  end
end
