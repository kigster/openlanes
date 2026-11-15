# frozen_string_literal: true

module OpenLanes
  module Engine
    class Extensions
      # What the page says a request is about: its heading and the sentence
      # under it. Three things raise one, and the card names the one that
      # did. A request raised for an agent whose starts kept failing once
      # said it "is out of rounds", of an agent that had not run at all.
      #
      # @!attribute [r] subject
      #   @return [OpenLanes::Plans::Subject]
      # @!attribute [r] request
      #   @return [Hash] the request, as `state.json` has it
      Card = Data.define(:subject, :request) do
        # @return [String]
        def heading
          agent = request["agent"]
          return "#{agent} is running out of time" if time?

          failed_starts? ? "#{agent} keeps failing to start" : "#{agent} is out of rounds"
        end

        # @return [String]
        def body
          return time if time?

          failed_starts? ? failed_starts : rounds
        end

        private

        def time? = request["limit"] == "time"

        def failed_starts? = request["cause"] == FAILED_STARTS

        def time
          "Round #{request["round"]} on #{subject.status} has under #{ASK_AT / 60} minutes left on its clock. " \
            "More time lets it carry on where it is; another round starts it again from its resume note."
        end

        def rounds
          "It has used every round it had on #{subject.status} without finishing. " \
            "Each choice gives it one more round; the time choices also lengthen that round's clock."
        end

        def failed_starts
          "Its starts on #{subject.status} kept failing before it spent anything, so it is no longer tried. " \
            "Check its CLI, then pick a choice: each lets it try again; the time choices also lengthen that round's clock."
        end
      end
    end
  end
end
