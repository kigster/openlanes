# frozen_string_literal: true

require "json"

module OpenLanes
  module Execution
    class AgentProcess
      # The CLI's exit, read back from the status file. Answers what the
      # executor asks of a `Process::Status`.
      ExitStatus = Data.define(:exitstatus, :termsig) do
        # @param path [String]
        # @return [ExitStatus, nil] nil when there is no status to read
        def self.read(path)
          data = JSON.parse(File.read(path))
          new(exitstatus: data["exitstatus"], termsig: data["termsig"])
        rescue SystemCallError, JSON::ParserError
          nil
        end

        # @return [Boolean]
        def success? = exitstatus&.zero? || false

        # @return [Boolean]
        def signaled? = !termsig.nil?
      end
    end
  end
end
