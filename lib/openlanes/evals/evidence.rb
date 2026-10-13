# frozen_string_literal: true

module OpenLanes
  module Evals
    # Everything a check may look at: the folder, where it ended, who was
    # asked to write it, what the run spent and what it changed.
    #
    # @!attribute [r] folder
    #   @return [String] the plan folder, which may not exist
    # @!attribute [r] state
    #   @return [Symbol, nil]
    # @!attribute [r] agent
    #   @return [OpenLanes::Agents::Agent]
    # @!attribute [r] run
    #   @return [OpenLanes::Evals::Run]
    # @!attribute [r] changes
    #   @return [OpenLanes::Evals::Changes, nil] nil when no repository was recorded
    Evidence = Data.define(:folder, :state, :agent, :run, :changes) do
      # @param name [String] a file in the plan folder
      # @return [String, nil]
      def read(name)
        path = File.join(folder, name)
        File.file?(path) ? File.read(path, encoding: "UTF-8") : nil
      end

      # A document without its ledger blocks, narrowed to one section when
      # asked. The ledger is the harness's bookkeeping, not the agent's prose,
      # and counting it would let a run pad itself by signing.
      #
      # @param name [String]
      # @param section [String, nil] a heading's text
      # @return [String, nil] nil when the file or the section is missing
      def text(name, section = nil)
        body = read(name) or return nil
        body = Plans::Ledger.stripped(body)
        section ? Evidence.section(body, section) : body
      end

      # The folder as the state machine would see it under +status+'s name,
      # so the status's own invariant can be asked of a folder whose name
      # carries no state, such as a recording's `plan/`.
      #
      # @param status [OpenLanes::Plans::Status]
      # @return [OpenLanes::Plans::Subject]
      def subject_as(status)
        Plans.subject(Plans::Feature.new(ordinal: Plans.ordinal("1"),
          status:,
          slug:    "eval",
          dirname: File.basename(folder),
          path:    folder))
      end

      # @param name [String]
      # @return [Regexp] a Markdown heading with that text, any level
      def self.heading(name) = /\A[ \t]{0,3}\#{1,6}[ \t]+#{Regexp.escape(name)}(?!\w)/i

      # The body under a heading, up to the next heading of the same or a
      # higher level.
      #
      # @param text [String]
      # @param name [String]
      # @return [String, nil]
      def self.section(text, name)
        lines = text.lines
        start = lines.index { |l| l.match?(heading(name)) } or return nil
        level = lines[start][/\A[ \t]*(#+)/, 1].size
        lines.drop(start + 1).take_while { |l| (l[/\A[ \t]{0,3}(#+)[ \t]/, 1]&.size || 7) > level }.join
      end
    end
  end
end
