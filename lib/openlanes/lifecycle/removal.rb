# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # `plans abandon`, `plans discard` and `plans trash`: takes plans out of
    # the active list from whatever state they claim (X1 to X9).
    #
    # The reason file is what justifies the state, so this writes it and lets
    # {Resync::Dirs} do the rest. A plan moved by hand-writing that file and one
    # moved by this command therefore land in the same place, with the same
    # date and the same rewiring.
    class Removal
      # A plan that moved, or on a dry run would have.
      #
      # @!attribute [r] ordinal
      #   @return [String]
      # @!attribute [r] title
      #   @return [String]
      # @!attribute [r] from
      #   @return [OpenLanes::Plans::Status]
      # @!attribute [r] to
      #   @return [OpenLanes::Plans::Status]
      Moved = Data.define(:ordinal, :title, :from, :to)

      # @!attribute [r] moved
      #   @return [Array<Moved>]
      # @!attribute [r] skipped
      #   @return [Array<String>] already in the requested state
      # @!attribute [r] refused
      #   @return [Hash{String => String}] ordinal => why
      # @!attribute [r] edits
      #   @return [Array<Rewiring::Edit>] dependents rewritten
      # @!attribute [r] open_prs
      #   @return [Hash{String => Array<String>}] ordinal => pull requests left open
      Result = Data.define(:moved, :skipped, :refused, :edits, :open_prs)

      # @param tree [OpenLanes::Plans::Tree]
      # @param to [Symbol] one of {Plans::REMOVED}
      def initialize(tree:, to:)
        @tree = tree.everything
        @to = Plans.status(to)
      end

      # @param reasons [Hash{String => String}] canonical ordinal => reason
      # @param dry_run [Boolean] report what would happen and write nothing
      # @return [Result]
      def call(reasons, dry_run: false)
        result = Result.new(moved: [], skipped: [], refused: {}, edits: [], open_prs: {})
        reasons.each { |ordinal, reason| remove(ordinal, reason, result, dry_run:) }
        result.edits.concat(Rewiring.new(tree: @tree).plan(result.moved.map(&:ordinal))) if dry_run
        result
      end

      private

      # @return [void]
      def remove(ordinal, reason, result, dry_run:)
        subject = @tree.reload.find(ordinal)
        return result.skipped << ordinal if subject.status == @to

        refusal = refusal_for(subject) || (write_and_check(subject, reason) unless dry_run)
        return result.refused[ordinal] = refusal if refusal

        # Before the move: once the folder has gone, this subject's path has too.
        note(subject, result)
        return if dry_run

        result.edits.concat(@pending)
        Resync::Dirs.new(tree: @tree, only: [ordinal]).call(commit: true)
      end

      # @return [void]
      def note(subject, result)
        feature = subject.feature
        ordinal = feature.ordinal.to_s
        result.moved << Moved.new(ordinal:, title: feature.title, from: subject.status, to: @to)
        open = subject.pull_requests.select(&:open?).map { "##{it.number}" }
        result.open_prs[ordinal] = open unless open.empty?
      end

      # @return [String, nil] why it cannot go
      def refusal_for(subject)
        from = subject.status
        return "cannot go from #{from} to #{@to}" unless Plans::StateMachine.edge?(from.key, @to.key)

        lock = Plans::Lock.read(subject.feature.path)
        "an agent is working on it (pid #{lock.pid} on #{lock.host})" if lock && !lock.stale?
      end

      # Writes the reason file, then looks for a clash before the first rename:
      # one found on the second step would leave the plan renamed but not moved.
      #
      # @return [String, nil] why it cannot go, with the reason file taken back
      def write_and_check(subject, reason)
        ordinal = subject.feature.ordinal.to_s
        @pending = Rewiring.new(tree: @tree).plan([ordinal])
        path = File.join(subject.feature.path, Plans.reason_file(@to.key))
        File.write(path, document(reason, subject.status, @pending))
        taken = clash(ordinal) or return nil
        File.delete(path)
        "#{File.basename(taken)} already exists"
      end

      # @return [String, nil] a path the plan's move would land on and cannot
      def clash(ordinal) = Resync::Dirs.new(tree: @tree, only: [ordinal]).plan.map(&:target).find { File.exist?(it) }

      # @return [String] the reason file
      def document(reason, from, edits)
        lines = ["# #{@to.label}", "", reason.strip, "", "- Date: #{Date.today.strftime("%F")}", "- Previous state: #{from}"]
        unless edits.empty?
          lines += ["", "## Dependents rewired", "", *edits.map { "- #{it}" }]
        end
        "#{lines.join("\n")}\n"
      end
    end
  end
end
