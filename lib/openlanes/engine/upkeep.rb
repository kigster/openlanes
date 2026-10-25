# frozen_string_literal: true

module OpenLanes
  module Engine
    # Keeps open pull requests from going stale while nobody is working on
    # them (decisions U1 to U4). Both duties are the harness's, since agents
    # may neither push nor label.
    #
    # - {Addressing}: a `review-rejected` pull request whose fixes were
    #   pushed after the rejection becomes `review-addressed` (U1).
    # - {Sweep}: whenever `main` moves, the pull requests waiting to merge
    #   are asked whether they still merge clean (U2, U4). {Verdict} reads
    #   GitHub's answer, {Actions} acts on it there, and {Owed} remembers who
    #   still owes one.
    # - {Resolution}: what follows a conflicted pull request's rebase in its
    #   plan's checkout (U3). Scheduling that rebase is the dispatcher's.
    #
    # The dispatcher talks to {Keeper} alone; nothing here knows the
    # dispatcher, the runner or the publisher.
    module Upkeep
      # The branch every plan's pull requests target.
      MAIN = "main"

      # One pull request that no longer merges clean onto {MAIN}.
      #
      # @!attribute [r] ordinal
      #   @return [String] its plan
      # @!attribute [r] number
      #   @return [Integer]
      # @!attribute [r] url
      #   @return [String]
      Conflict = Data.define(:ordinal, :number, :url)

      # How a step went, for the dispatcher to log or fold into an attempt.
      #
      # @!attribute [r] ok
      #   @return [Boolean, nil] false when it failed; nil when it says
      #     nothing about success, as an abort that will be tried again
      # @!attribute [r] note
      #   @return [String]
      Report = Data.define(:ok, :note)

      module_function

      # The GitHub client and the clock come from {Container} unless given,
      # so a spec stubs `github` or `clock` there instead of threading a
      # double through every caller. +push+ is bound to the run's publisher,
      # which is not a component, so it is always passed.
      #
      # @param push [#call] pushes a checkout's HEAD to its branch, raising
      #   {OpenLanes::Error} when refused
      # @param github [Vcs::GitHub]
      # @param clock [#call]
      # @return [Keeper]
      def keeper(push:, github: Container["github"], clock: Container["clock"].method(:now))
        owed = Owed.new
        Keeper.new(addressing: Addressing.new(github:),
          sweep: Sweep.new(github:, owed:, actions: Actions.new(github:, clock:)),
          resolution: Resolution.new(owed:, push:),
          owed:)
      end

      # @param error [Exception]
      # @return [String] the first line of its message
      def first_line(error) = error.message.lines.first.to_s.strip
    end
  end
end
