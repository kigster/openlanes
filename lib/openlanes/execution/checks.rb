# frozen_string_literal: true

module OpenLanes
  module Execution
    # The requirement every agent that changes code carries whether or not the
    # spec says it: after the changes, every test suite and linter passes.
    #
    # A spec author writes the things that are particular to a plan. That the
    # suite stays green is particular to none of them, so it was written in
    # none of them, and a builder that never ran the linter shipped work the
    # reviewer then had to reject for it. Deriving the command from the
    # checkout, rather than asking each spec to name it, keeps it one fact in
    # one place: the project's own justfile or Gemfile.
    module Checks
      # Agents whose work is code, or the judging of code. Research, planning
      # and unblocking write documents, and running a suite for a document is
      # minutes spent proving nothing.
      PHASES = %w[build frontend review].freeze

      # The recipe a project names its everything-gate with.
      RECIPE = "check-all"

      JUSTFILES = %w[justfile Justfile .justfile].freeze

      # A recipe header: optional `@`, the name, optional parameters, a colon
      # that is not the start of `:=` (an assignment).
      RECIPE_LINE = /^@?#{Regexp.escape(RECIPE)}(?:\s[^:\n]*)?:(?!=)/

      RUBY = ["bundle exec rspec", "bundle exec rubocop"].freeze

      class << self
        # @param agent [OpenLanes::Agents::Agent]
        # @return [Boolean] whether the agent carries the requirement
        def apply_to?(agent) = PHASES.include?(agent.phase.to_s)

        # @param root [String] the checkout the agent works in
        # @return [Array<String>] the commands that must pass, empty when the
        #   project names none this can recognise
        def commands(root)
          return ["just #{RECIPE}"] if recipe?(root)
          return RUBY if File.file?(File.join(root, "Gemfile"))

          []
        end

        # @param root [String]
        # @return [String] the requirement, one line
        def requirement(root)
          commands = commands(root)
          if commands.empty?
            "After your changes, every test suite and linter the project defines passes. " \
              "Find them in its README, AGENTS.md or CLAUDE.md, run them all, and fix what they report."
          else
            "After your changes, all tests and linters pass: #{commands.map { "`#{it}`" }.join(" and ")} " \
              "#{commands.size == 1 ? "exits" : "each exit"} 0. Run #{commands.size == 1 ? "it" : "them"} " \
              "before you sign Completed, and fix what they report rather than reporting it."
          end
        end

        private

        # @param root [String]
        # @return [Boolean]
        def recipe?(root)
          JUSTFILES.any? do |name|
            path = File.join(root, name)
            File.file?(path) && File.read(path, encoding: "UTF-8").match?(RECIPE_LINE)
          end
        end
      end
    end
  end
end
