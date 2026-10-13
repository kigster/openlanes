# frozen_string_literal: true

module OpenLanes
  module Evals
    # Applies a case's checks to a folder.
    #
    # The scorer does not care whether the folder was recorded months ago or
    # written a second ago by a live run; both reach it as a path plus a
    # {Run}, which is what lets the recordings test the scorer that the live
    # runs depend on.
    class Scorer
      # @param kase [OpenLanes::Evals::Case]
      # @param registry [OpenLanes::Agents::Registry]
      def initialize(kase, registry: Agents.registry)
        @kase = kase
        @agent = registry.find(kase.agent) or raise Invalid, "#{kase.path}: names no agent called #{kase.agent}"
      end

      # @param folder [String] the plan folder
      # @param run [OpenLanes::Evals::Run, nil]
      # @param repo [String, nil] the repository afterwards
      # @return [OpenLanes::Evals::Score]
      def call(folder:, run: nil, repo: nil)
        run ||= Run.new
        evidence = Evidence.new(folder: File.expand_path(folder),
          state:   state_of(folder, run),
          agent:   @agent,
          run:,
          changes: repo && Changes.between(@kase.fixture.repo, repo))
        Score.new(kase: @kase, verdicts: @kase.checks.map { |check| check.call(evidence) })
      end

      private

      # A folder named like a plan says where it is; a recording's `plan/`
      # cannot, and leans on what `run.json` says instead.
      #
      # @return [Symbol, nil]
      def state_of(folder, run) = Plans.feature(File.expand_path(folder))&.status&.key || run.state
    end
  end
end
