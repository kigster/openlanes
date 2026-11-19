# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # How a `/compact` went, in the words a person reads in the reply to
      # their request.
      module CompactReply
        module_function

        # @param status [Process::Status] how `/compact` exited
        # @param transcript [OpenLanes::Execution::Transcript] its session
        # @return [String, nil] why it did not compact, nil when it did
        def failure(status, transcript)
          return "/compact exited #{status.exitstatus}: #{Said.of(transcript)}" unless status.success?
          return "/compact reported: #{transcript.error}" if transcript.failed?

          "/compact did not compact: #{Said.of(transcript)}" unless transcript.compacted
        end

        # @param attempt [OpenLanes::Execution::Executor::Attempt]
        # @param model [String] what the session carries on in
        # @param compaction [OpenLanes::Execution::Executor::Compaction]
        # @return [String] the reply once it carries on
        def note(attempt, model, compaction)
          sizes = attempt.sessions.previous.compacted.values_at("pre_tokens", "post_tokens")
          tokens = sizes.all? ? " from #{sizes.first} to #{sizes.last} tokens" : ""
          "#{attempt.agent.name} compacted#{tokens} and carries on#{" on #{model}" if compaction.model}"
        end
      end
    end
  end
end
