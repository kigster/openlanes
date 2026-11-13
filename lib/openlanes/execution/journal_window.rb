# frozen_string_literal: true

module OpenLanes
  module Execution
    # Which of an agent's journal entries one round's prompt has to carry.
    #
    # A round that starts a session carries the whole journal. A round that
    # resumes one need not: the session was sent the earlier entries in a
    # prompt, or printed them itself, and the journal was measured at about
    # 5k tokens a round paid again for nothing. So a resumed round carries
    # only the entries numbered after the last one its session holds.
    #
    # What a session holds is not guessed from the stages. The executor
    # records it ({Plans::PlanState#hold!}) when a round ends with its
    # session never compacted, and forgets it when a round starts, so a
    # round that died, was compacted, or ran on a CLI that cannot resume
    # leaves no record. Without a record naming the very session being
    # resumed the window is the whole journal: an entry sent twice costs
    # tokens, an entry never sent costs the agent a decision it made.
    class JournalWindow
      # @param state [OpenLanes::Plans::PlanState]
      # @param agent [String]
      # @param resume [String, nil] the session this round carries on, nil
      #   for a fresh start
      # @return [OpenLanes::Execution::JournalWindow]
      # @raise [OpenLanes::Error] when state.json is not valid JSON
      def self.for(state, agent:, resume: nil)
        new(rounds: state.journal(agent), held: (state.held(agent) if resume), resume:)
      end

      # @param rounds [Array<OpenLanes::Plans::Journal::Round>]
      # @param held [OpenLanes::Plans::Journal::Held, nil]
      # @param resume [String, nil]
      def initialize(rounds:, held: nil, resume: nil)
        @numbered = rounds.flat_map { |r| r.entries.each_with_index.map { |e, i| [r, r.first + i, e] } }
        @since = since_for(held, resume)
      end

      # @return [Array<Array(OpenLanes::Plans::Journal::Round, Integer, OpenLanes::Plans::Journal::Entry)>]
      #   every entry with its round and its number, oldest first
      attr_reader :numbered

      # @return [Integer, nil] the number of the last entry the resumed
      #   session holds; nil when the whole journal has to be sent
      attr_reader :since

      # @return [Boolean] whether the round resumes a session known to hold
      #   the journal up to {#since}
      def resumed? = !since.nil?

      # @return [Integer] entries in the whole journal
      def total = numbered.size

      # @return [Array] of {#numbered}, the entries this round's prompt
      #   carries: all of them, or on a resume the ones after {#since}
      def entries = resumed? ? numbered.select { |_, n, _| n > since } : numbered

      private

      # A record for another session says nothing about this one. One that
      # counts more entries than the journal has describes a journal somebody
      # has since cut, and is not believed either.
      #
      # @return [Integer, nil]
      def since_for(held, resume)
        return nil unless resume && held && held.session == resume

        held.through if held.through.between?(0, total)
      end
    end
  end
end
