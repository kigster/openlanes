# frozen_string_literal: true

require "date"
require "time"

module OpenLanes
  module Lifecycle
    # Blocked plans age (N8). A ⭕ or 🛑 that other plans are waiting for
    # becomes 💣 after {BOMB_AFTER}, and the run halts on it; one nobody waits
    # for is deferred after {DEFER_AFTER}, with a `delayed.md` naming what
    # brings it back.
    #
    # This is a sweep that fires events, not an invariant that reads the
    # clock. A state whose check looked at the time would rename folders as
    # days passed with nobody firing anything, and asking a question about a
    # folder must never fire one. So 💣 holds by its contents alone, and only
    # this sweep, run by the engine before it assigns work, moves a plan in.
    class Aging
      # How long a plan others depend on may sit blocked before it halts the
      # run. 24 hour multiples, not calendar days: the limit is the same length
      # across a daylight saving change.
      BOMB_AFTER = 7 * 86_400

      # How long a plan nobody depends on may sit blocked before it is set
      # aside.
      DEFER_AFTER = 14 * 86_400

      # The states that age. 💣 is not among them: it is already the loudest
      # thing a block can become, and deferring it would quietly drop a plan
      # others are waiting for.
      AGES = %i[blocked product_blocked].freeze

      # Dependents in these states wait for nothing any more: they shipped
      # (008's {Plans::Dependencies::DONE}) or were dropped.
      CLOSED = (Plans::Dependencies::DONE + %i[discarded]).freeze

      # What one sweep did, or on a dry run would have done.
      #
      # @!attribute [r] bombed
      #   @return [Array<String>] ordinals now 💣
      # @!attribute [r] deferred
      #   @return [Array<String>] ordinals now 💤
      Result = Data.define(:bombed, :deferred) do
        def initialize(bombed: [], deferred: []) = super

        # @return [Boolean]
        def empty? = bombed.empty? && deferred.empty?
      end

      # @param tree [OpenLanes::Plans::Tree]
      # @param since [Date, nil] `plans.aging_since`: no plan ages from
      #   before local midnight on this day
      # @param now [Time]
      def initialize(tree:, since: nil, now: Time.now)
        @tree = tree
        @since = since
        @now = now
      end

      # Bomb or defer every blocked plan among +subjects+ past its limit.
      #
      # @param subjects [Array<OpenLanes::Plans::Subject>, nil] the plans to
      #   age; every plan in the tree when nil
      # @param commit [Boolean] false reports what would happen and changes
      #   nothing
      # @return [Result]
      def call(subjects: nil, commit: true)
        bombed = []
        deferred = []
        (subjects || @tree.subjects).each do |subject|
          next unless AGES.include?(subject.status.key)

          age = age_of(subject)
          if waited_for?(subject)
            next if age < BOMB_AFTER

            bombed << subject.feature.ordinal.to_s if !commit || bomb!(subject, age)
          elsif age >= DEFER_AFTER
            deferred << subject.feature.ordinal.to_s if !commit || defer!(subject, age)
          end
        end
        @tree.reload if commit && !(bombed.empty? && deferred.empty?)
        Result.new(bombed:, deferred:)
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Float] seconds the plan has been blocked, as far as aging counts
      def age_of(subject) = @now - started_at(subject)

      # When the clock started: the latest `Blocked` signature, so a plan
      # blocked again after an answer starts over, or `blocked.md`'s mtime
      # when nobody signed, as the control room already reads it. Never
      # before `aging_since`.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Time]
      def started_at(subject)
        signed = Plans::PlanState.for(subject.feature.path).signatures.rfind { it["status"] == "Blocked" }
        start = signed ? parse(signed["at"]) : nil
        start ||= File.mtime(File.join(subject.feature.path, "blocked.md"))
        floor = @since && Time.local(@since.year, @since.month, @since.day)
        floor && floor > start ? floor : start
      end

      private

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean] whether a plan still open names this one in `depends_on:`
      def waited_for?(subject)
        @tree.blocks_of(subject.feature.ordinal).any? do |ordinal|
          dependent = @tree.find(ordinal)
          dependent && !CLOSED.include?(dependent.status.key)
        end
      end

      # @return [Boolean] whether the folder moved
      def bomb!(subject, age)
        subject.machine.promote!(:bomb)
        UI.log("aging: 💣 after #{days(age)} blocked, with plans waiting on it", plan: subject.feature.ordinal.to_s)
        true
      rescue Plans::StateMachine::Refused => e
        UI.log("aging: could not bomb: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
        false
      end

      # `delayed.md` goes in first: 💤 refuses a folder without a trigger.
      #
      # @return [Boolean] whether the folder moved
      def defer!(subject, age)
        path = File.join(subject.feature.path, "delayed.md")
        wrote = !File.exist?(path)
        File.open(path, "a") { it.write(delayed(subject, age, fresh: wrote)) }
        subject.machine.promote!(:deferred)
        UI.log("aging: 💤 after #{days(age)} blocked, with no plan waiting on it", plan: subject.feature.ordinal.to_s)
        true
      rescue Plans::StateMachine::Refused => e
        File.delete(path) if wrote && File.exist?(path)
        UI.log("aging: could not defer: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
        false
      end

      # @return [String]
      def delayed(subject, age, fresh:)
        heading = fresh ? "# Deferred: #{subject.feature.ordinal} #{subject.feature.slug}\n\n" : "\n"
        "#{heading}Deferred by aging on #{@now.strftime("%Y-%m-%d")}: blocked #{days(age)} with no answer, " \
          "and no open plan depends on it.\n\n" \
          "Trigger: revisit after the block is answered. The questions are still in `blocked.md`.\n"
      end

      # @param seconds [Numeric]
      # @return [String] "8 days"
      def days(seconds)
        count = (seconds / 86_400).floor
        "#{count} day#{"s" unless count == 1}"
      end

      # @param text [String, nil]
      # @return [Time, nil]
      def parse(text)
        Time.iso8601(text.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
