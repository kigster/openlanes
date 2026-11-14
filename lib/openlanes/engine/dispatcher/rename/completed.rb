# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # One round that signed Completed, as the steps that move its folder
        # read it: the job, the attempt so far, the plan read fresh, the
        # closing ledger line, and the ledger it was read from.
        Completed = Data.define(:job, :base, :subject, :entry, :reading) do
          # @return [String] the plan's ordinal
          def ordinal = subject.feature.ordinal.to_s

          # @return [OpenLanes::Agents::Agent]
          def agent = job.task.agent
        end
      end
    end
  end
end
