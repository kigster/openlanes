# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What {Executor} answers about how an invocation went, from its
      # {Verdict}. The including class holds it as +@verdict+.
      module Reporting
        # @see Verdict#failure
        def failure(transcript, started, note, **) = @verdict.failure(transcript, started, note:, **)

        # @see Verdict#spent
        def spent(transcript, started, **) = @verdict.spent(transcript, started, **)

        # @see Said.of
        def said(transcript) = Said.of(transcript)

        # @see Verdict#killed_note
        def killed_note(reason, _clock = nil) = @verdict.killed_note(reason)
      end
    end
  end
end
