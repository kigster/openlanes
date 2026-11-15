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
      # @!attribute [r] tolerate
      #   @return [Integer, nil] how many excused failed starts in a row are
      #     let go; from that many on they all count. nil excuses any number.
      Count = Data.define(:since, :except, :tolerate) do
        def initialize(since: nil, except: nil, tolerate: nil) = super
      end
    end
  end
end
