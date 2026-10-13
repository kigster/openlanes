# frozen_string_literal: true

module OpenLanes
  module Evals
    # A plan folder as some run of the agent left it, kept so the scorers can
    # be checked without running anything.
    #
    #   <case>/pass/plan/       the plan folder
    #   <case>/pass/repo/       the repository around it, for coding agents
    #   <case>/pass/run.json    {"seconds": .., "tokens": .., "state": ..}
    #
    # The folder sits in `plan/` rather than at the top so that `run.json` and
    # `repo/` are never mistaken for files the agent wrote.
    #
    # @!attribute [r] dir
    #   @return [String]
    Recording = Data.define(:dir) do
      # @param dir [String]
      # @return [OpenLanes::Evals::Recording, nil] nil when there is no plan folder
      def self.at(dir) = File.directory?(File.join(dir, "plan")) ? new(dir:) : nil

      # @return [String] the plan folder
      def plan = File.join(dir, "plan")

      # @return [String, nil] the repository, when one was recorded
      def repo
        path = File.join(dir, "repo")
        File.directory?(path) ? path : nil
      end

      # @return [OpenLanes::Evals::Run]
      def run = Run.load(File.join(dir, "run.json"))

      # @return [Symbol] :pass or :fail
      def kind = File.basename(dir).to_sym
    end
  end
end
