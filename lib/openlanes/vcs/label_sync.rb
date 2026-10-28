# frozen_string_literal: true

module OpenLanes
  module Vcs
    # Makes the repository's labels match {Plans::ReviewLabel::SYNCED}: R3's
    # review labels and `openlanes`. Renames a label still under its old name
    # ({Plans::ReviewLabel::RENAMED}), creates the missing, recolours the
    # mismatched, leaves the rest. A rename rather than a create, because a
    # renamed label stays on every pull request that carries it.
    #
    # Run once when the engine starts on a project. Labelling a pull request
    # still creates a missing label on first use, but never recolours one, so
    # without this a repository labelled under M3 would keep `review-rejected`
    # in M3's red forever and a person reading the board would see two reds
    # meaning one thing. One `gh label list`, and a write only per label that
    # is wrong, so a second run asks once and changes nothing.
    class LabelSync
      # What was done to one label, or under a dry run what would have been.
      #
      # @!attribute [r] action
      #   @return [Symbol] :create, :rename, :recolour or :keep
      # @!attribute [r] was
      #   @return [String, nil] the colour the repository had, for :recolour;
      #     the old name, for :rename
      Change = Data.define(:label, :action, :was) do
        # @return [Boolean] whether this label needs a write
        def write? = action != :keep

        # @return [String] one line for the startup notice
        def to_s
          case action
          when :create then "create #{label.name} (##{label.colour})"
          when :rename then "rename #{was} → #{label.name}"
          when :recolour then "recolour #{label.name} ##{was} → ##{label.colour}"
          else "keep #{label.name}"
          end
        end
      end

      # @param github [GitHub]
      # @param labels [Array<Plans::ReviewLabel>]
      def initialize(github: GitHub.new, labels: Plans::ReviewLabel::SYNCED)
        @github = github
        @labels = labels
      end

      # @param repo [String, nil] "owner/repo"; nil means the current checkout's
      # @param dry_run [Boolean] read the repository's labels, write nothing
      # @return [Array<Change>] one per label, in R3 order
      # @raise [OpenLanes::Error] when `gh` cannot list or write a label
      def call(repo: nil, dry_run: false)
        have = @github.label_colours(repo:)
        changes = @labels.map { change_for(it, have) }
        return changes if dry_run

        changes.each { write(it, repo) }
        changes
      end

      private

      # @param change [Change]
      # @param repo [String, nil]
      # @return [void]
      def write(change, repo)
        case change.action
        when :create then @github.ensure_label(change.label, repo:)
        when :rename then @github.rename_label(change.was, change.label, repo:)
        when :recolour then @github.recolour_label(change.label, repo:)
        end
      end

      # GitHub answers colours in lower case and R3 writes some in upper, so
      # they are compared without case; otherwise every run would "fix" them.
      #
      # @return [Change]
      def change_for(label, have)
        colour = have[label.name]
        return renamed(label, have) if colour.nil?
        return Change.new(label:, action: :keep, was: colour) if colour.casecmp?(label.colour)

        Change.new(label:, action: :recolour, was: colour)
      end

      # A missing label still under its old name is renamed; otherwise created.
      #
      # @return [Change]
      def renamed(label, have)
        old = Plans::ReviewLabel::RENAMED.key(label)
        return Change.new(label:, action: :rename, was: old) if have.key?(old)

        Change.new(label:, action: :create, was: nil)
      end
    end
  end
end
