# frozen_string_literal: true

module OpenLanes
  # Per-agent evals: did the agent finish the task, and did it work at the
  # depth it was asked for?
  #
  # A case (`evals/cases/<agent>/<id>.yml`) describes a fixture plan, the depth
  # requested and the deterministic checks that hold an agent to both. Offline,
  # the checks score recorded plan folders, a passing and a failing one per
  # case, so the scorers are tested by the same corpus they score. Live, the
  # agent runs in a throwaway repository under a token cap, and the folder it
  # leaves behind is scored the same way.
  module Evals
    # Where the shipped cases live: beside the gem, so `openlanes eval` finds
    # them from any project root.
    DEFAULT_DIR = File.expand_path("../../evals/cases", __dir__)

    # A case file that cannot be scored as written.
    class Invalid < OpenLanes::Error; end

    module_function

    # @param dir [String] a directory of `<agent>/<id>.yml` files
    # @param registry [OpenLanes::Agents::Registry] the agents a case may name
    # @return [Array<OpenLanes::Evals::Case>] ordered by agent, then id
    # @raise [OpenLanes::Evals::Invalid] when any case fails validation
    def cases(dir = DEFAULT_DIR, registry: Agents.registry) = Case.all(dir, registry:)

    # @param kase [OpenLanes::Evals::Case]
    # @param folder [String] the plan folder as the agent left it
    # @param run [OpenLanes::Evals::Run, nil] what the run spent, and where it ended
    # @param repo [String, nil] the repository as the agent left it, for the
    #   changed-path checks
    # @param registry [OpenLanes::Agents::Registry]
    # @return [OpenLanes::Evals::Score]
    def score(kase, folder:, run: nil, repo: nil, registry: Agents.registry)
      Scorer.new(kase, registry:).call(folder:, run:, repo:)
    end

    # @param kase [OpenLanes::Evals::Case]
    # @param kind [Symbol] :pass or :fail
    # @param registry [OpenLanes::Agents::Registry]
    # @return [OpenLanes::Evals::Score, nil] nil when the case ships no such recording
    def score_recording(kase, kind = :pass, registry: Agents.registry)
      recording = kase.recording(kind) or return nil

      score(kase, folder: recording.plan, run: recording.run, repo: recording.repo, registry:)
    end

    # Runs the real agent. Nothing calls this unless `--live` was typed.
    #
    # @param kase [OpenLanes::Evals::Case]
    # @return [OpenLanes::Evals::Live::Outcome]
    def run_live(kase, **) = Live.new(kase, **).call
  end
end
