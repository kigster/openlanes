# frozen_string_literal: true

module OpenLanes
  module Plans
    class Rounds
      # Which failed starts count towards the cap of three ({Rounds#failed_starts}).
      #
      # @!attribute [r] since
      #   @return [Time, nil] only stages started after it: a granted request
      #     lifts the cap by starting the count again
      # @!attribute [r] except
      #   @return [Regexp, nil] a note that excuses a failed start, such as a
      #     failed login, which the CLI pause owns instead of the cap
      Count = Data.define(:since, :except) do
        def initialize(since: nil, except: nil) = super
      end
    end
  end
end
