# frozen_string_literal: true

module OpenLanes
  module Engine
    module Upkeep
      # Asks the pull requests that owe an answer whether they still merge
      # clean, and acts on each {Verdict} through {Actions} (U2, U4). Only
      # pull requests recorded in a plan are asked: resolving one needs the
      # plan's checkout and branch.
      class Sweep
        # What one sweep found.
        #
        # @!attribute [r] conflicts
        #   @return [Array<Conflict>] to be resolved
        # @!attribute [r] notes
        #   @return [Array<String>] one line per pull request acted on, for the log
        Result = Data.define(:conflicts, :notes)

        # @param github [Vcs::GitHub]
        # @param owed [Owed]
        # @param actions [Actions]
        def initialize(github:, owed:, actions:)
          @github = github
          @owed = owed
          @actions = actions
        end

        # @param subjects [Array<Plans::Subject>] the plans in scope
        # @param busy [Array<String>] ordinals an agent is working in; asked later
        # @return [Result]
        def call(subjects, busy: [])
          @owed.moved!(@github.branch_head(branch: MAIN), entries(subjects))
          by_ordinal = subjects.to_h { [it.feature.ordinal.to_s, it] }
          result = Result.new(conflicts: [], notes: [])
          @owed.due(busy:).each do |entry|
            subject = by_ordinal[entry.ordinal]
            next @owed.settle(entry) if subject.nil?

            ask(subject, entry, result)
          rescue OpenLanes::Error => e
            result.notes << "#{entry.ordinal}: #{entry.url} not checked against #{MAIN}: #{Upkeep.first_line(e)}"
          end
          result
        end

        private

        # @return [Array<Owed::Entry>] every open pull request of every live plan
        def entries(subjects)
          subjects.reject { it.status.terminal? }.flat_map do |subject|
            subject.pull_requests.select(&:open?).map { Owed::Entry.new(ordinal: subject.feature.ordinal.to_s, url: it.url.to_s) }
          end
        end

        # @return [void]
        def ask(subject, entry, result)
          live = @github.pull_request(entry.url)
          verdict = Verdict.of(live)
          @owed.settle(entry) unless verdict == :unknown
          number = live[:number]
          case verdict
          when :conflicted, :still_conflicted
            @actions.conflicted(number) if verdict == :conflicted
            result.conflicts << Conflict.new(ordinal: entry.ordinal, number:, url: entry.url)
          when :behind then result.notes << @actions.behind(subject, number)
          when :resolved then result.notes << @actions.resolved(number)
          end
        end
      end
    end
  end
end
