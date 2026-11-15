# frozen_string_literal: true

module OpenLanes
  module Engine
    # Runs the curator over every plan that has just ended, so a lesson is
    # proposed without anybody remembering to type `openlanes memory curate`.
    #
    # A plan is curated once per ending: the outcome is written into its
    # `state.json` as a `curated` stage, so a restarted run, or the next
    # round of this one, does not ask the curator about it again. A plan that
    # is rejected, fixed and then merged has two endings and is curated twice.
    #
    # Under `memory: false` it does nothing at all: no agent is started and
    # the inbox is never opened, so a `--no-memory` run writes no candidate.
    class Curating
      # The states a plan ends in, for the curator's purposes: each one
      # carries a verdict the next plan can learn from.
      ENDINGS = %i[approved rejected rewrite discarded].freeze

      # The stage status that marks a plan as curated for one ending.
      CURATED = "curated"

      # The stage status written just before the curator is asked, so a
      # plan whose curator failed, or whose run was cut short, still shows
      # the curator has been here.
      PENDING = "pending"

      # What a tree's plans had ended in before the curator ever ran here, so
      # the first run after an upgrade does not start it on every plan ever
      # merged. Once any plan carries a curator stage the snapshot is empty
      # and the `curated` stage alone decides: a plan ended by a run that was
      # killed, raised, or whose curator failed is curated by the next run.
      #
      # @param subjects [Enumerable<OpenLanes::Plans::Subject>]
      # @return [Set<Array(String, Symbol)>] ordinal and ending, one per ended plan
      def self.snapshot(subjects)
        subjects = subjects.to_a
        return Set.new if subjects.any? { curator_stages(it).any? }

        subjects.select { ENDINGS.include?(it.status.key) }.to_set { [it.feature.ordinal.to_s, it.status.key] }
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<Hash>] the curator's stages in this plan's `state.json`
      def self.curator_stages(subject)
        Plans::PlanState.for(subject.feature.path).stages.select { it["agent"] == Agents::Names::CURATOR }
      end

      # @param curation [#call, nil] takes a {Plans::Subject}, returns a
      #   {Memory::Curation::Report}; nil when memory is off
      # @param memory [Boolean] false curates nothing
      # @param before [Set<Array(String, Symbol)>] endings {.snapshot} saw before the run; skipped
      def initialize(curation:, memory: true, before: Set.new)
        @curation = curation
        @memory = memory
        @before = before
      end

      # @param subjects [Enumerable<OpenLanes::Plans::Subject>]
      # @return [Array<OpenLanes::Memory::Curation::Report>] one per plan curated
      def call(subjects)
        return [] unless @memory && @curation

        subjects.select { ended?(it) && !@before.include?(key(it)) && !curated?(it) }.map { curate(it) }
      end

      private

      # @return [Array(String, Symbol)]
      def key(subject) = [subject.feature.ordinal.to_s, subject.status.key]

      # @return [Boolean]
      def ended?(subject) = ENDINGS.include?(subject.status.key)

      # @return [Boolean] whether this plan was curated for the ending it is in now
      def curated?(subject)
        stages(subject).any? { it["status"] == CURATED && it["note"] == subject.status.key.to_s }
      end

      # @return [OpenLanes::Memory::Curation::Report]
      def curate(subject)
        pend(subject)
        report = @curation.call(subject)
        mark(subject) if report.ok
        report
      end

      # @return [void]
      def pend(subject)
        return if stages(subject).any? { it["status"] == PENDING }

        Plans::PlanState.for(subject.feature.path).stage!(agent: Agents::Names::CURATOR, round: 0, status: PENDING, note: subject.status.key.to_s)
      end

      # @return [void]
      def mark(subject)
        state = Plans::PlanState.for(subject.feature.path)
        round = stages(subject).count { it["status"] == CURATED } + 1
        state.stage!(agent: Agents::Names::CURATOR, round:, reset: true, status: CURATED, note: subject.status.key.to_s)
      end

      # @return [Array<Hash>] the curator's stages in this plan's `state.json`
      def stages(subject) = self.class.curator_stages(subject)
    end
  end
end
