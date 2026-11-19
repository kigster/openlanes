# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What a person or the engine has told an agent that it has not yet
      # had a process to read: the control file's word, when it is one the
      # next start must still find there.
      module StandingOrder
        # The words that outlast a wait.
        STANDING = [Control::HOLD, Control::WRAP_UP, Control::PAUSE].freeze

        module_function

        # @param handle [OpenLanes::Execution::Executor::Handle]
        # @return [String, nil]
        def of(handle)
          word = handle.control && File.read(handle.control).strip
          word if word&.start_with?(*STANDING)
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
