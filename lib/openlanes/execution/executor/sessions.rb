# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The transcripts of one invocation's sessions, added up: the agent's own
      # and, once compacted, the `/compact` and the continuation after it. One
      # car on the board, so one meter, which must not drop when the second
      # session starts counting from zero.
      class Sessions
        def initialize = @all = []

        # @param transcript [OpenLanes::Execution::Transcript]
        # @return [OpenLanes::Execution::Executor::Sessions]
        def <<(transcript)
          @all << transcript
          self
        end

        # @return [OpenLanes::Execution::Transcript] the session running now
        def current = @all.last

        # @return [OpenLanes::Execution::Transcript, nil] the one before it
        def previous = @all[-2]

        # @return [OpenLanes::Execution::Transcript::Progress, nil] what the
        #   board was last told, so a wait can be drawn over the same meter
        attr_reader :shown

        # @return [Integer]
        def up = @all.sum(&:up)

        # @return [Integer]
        def down = @all.sum(&:down)

        # @return [Integer]
        def cached = @all.sum(&:cached)

        # @return [Integer]
        def fresh = up - cached + down

        # @return [Integer]
        def spawned = @all.sum(&:spawned)

        # @return [Integer]
        def delegated = @all.sum(&:delegated)

        # @return [Integer]
        def tools = @all.sum(&:tools)

        # What the agent said at the end of each session, joined: where it
        # names the lessons it applied. Before a compaction counts too, since
        # a report written then is still this invocation's.
        #
        # @return [String]
        def report = @all.filter_map { it.result if it.respond_to?(:result) }.join("\n")

        # @return [Boolean] whether any session of the invocation was
        #   compacted, at a person's request or at the CLI's own threshold
        def compacted? = @all.any? { it.respond_to?(:compacted) && it.compacted }

        # What the sessions already over spent, added to the running one's
        # progress so the meter carries on rather than starting again. Their
        # journal lines go first, for the same reason: the dispatcher counts
        # its place in the list, and a list that started again at the
        # continuation would have it skip the continuation's first entries.
        # `running` is left as the live session reports it: a session that is
        # over has no sub-agent still in flight.
        #
        # @param progress [OpenLanes::Execution::Transcript::Progress]
        # @return [OpenLanes::Execution::Transcript::Progress]
        def carry(progress)
          before = @all[0...-1]
          @shown = progress.with(up: progress.up + before.sum(&:up),
            down: progress.down + before.sum(&:down),
            subagents: progress.subagents + before.sum(&:spawned),
            journal: (before.flat_map { it.respond_to?(:journal) ? it.journal : [] } + progress.journal).freeze)
        end
      end
    end
  end
end
