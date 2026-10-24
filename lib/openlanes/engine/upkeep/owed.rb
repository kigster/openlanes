# frozen_string_literal: true

module OpenLanes
  module Engine
    module Upkeep
      # The only memory the sweep keeps between polls: which pull requests
      # still owe an answer, against which head of `main`. GitHub says
      # `UNKNOWN` for a while after `main` moves, and a resolution is only
      # judged once GitHub has seen it, so both stay owed until answered.
      #
      # Reads and writes nothing outside itself.
      class Owed
        # One pull request of one plan.
        #
        # @!attribute [r] ordinal
        #   @return [String]
        # @!attribute [r] url
        #   @return [String]
        Entry = Data.define(:ordinal, :url)

        def initialize
          @head = nil
          @entries = Set.new
          @pushed = Set.new
        end

        # `main` moved: every one of +entries+ owes an answer.
        #
        # @param head [String] `main`'s commit now
        # @param entries [Array<Entry>] every open pull request in scope
        # @return [Boolean] whether it moved
        def moved!(head, entries)
          return false if head == @head

          @head = head
          @entries.merge(entries)
          true
        end

        # @param busy [Array<String>] ordinals an agent is working in, asked later
        # @return [Array<Entry>]
        def due(busy: []) = @entries.reject { busy.include?(it.ordinal) }

        # @param entry [Entry]
        # @return [void]
        def settle(entry) = @entries.delete(entry)

        # @param conflict [Conflict]
        # @return [void]
        def recheck(conflict) = @entries << Entry.new(ordinal: conflict.ordinal, url: conflict.url)

        # Whether a clean rebase of this pull request's branch may be pushed
        # now: once per head of `main`. A checkout that rebases clean while
        # GitHub still says `DIRTY` would otherwise be pushed and asked about
        # again on every poll, for ever.
        #
        # @param conflict [Conflict]
        # @return [Boolean]
        def pushable?(conflict) = !@pushed.add?([conflict.url, @head]).nil?
      end
    end
  end
end
