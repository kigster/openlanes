# frozen_string_literal: true

module OpenLanes
  module Execution
    class AgentProcess
      # The three files one agent supervisor writes or is known by.
      Files = Data.define(:output, :status, :pid_file)
    end
  end
end
