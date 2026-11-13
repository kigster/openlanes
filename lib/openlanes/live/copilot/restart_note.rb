# frozen_string_literal: true

module OpenLanes
  module Live
    class Copilot
      # What the supervisor left for the control room it restarted
      # (`/restart-web`, plan 069.00): how the page's build went. The web
      # server that read the command died with it, so the new one takes the
      # note on boot and tells the person in the copilot. The note's format
      # is {Supervision::WebRestartNote}'s, read through the facade.
      class RestartNote
        # @param take [#call] returns the note, removed as it is read, or nil
        # @param copilot [OpenLanes::Live::Copilot] where the turn goes
        def initialize(take:, copilot:)
          @take = take
          @copilot = copilot
        end

        # The note is removed before it is told, so a server that crashes
        # after telling it cannot tell it twice.
        #
        # @return [OpenLanes::Live::Copilot::Turn, nil] the turn appended;
        #   nil when there was no note, or none that could be read
        def call
          note = @take.call or return

          @copilot.tell(Turn.new(id: "web-restart-#{note.at.to_i}", from: "copilot", kind: "text", text: text_for(note.outcome), at: note.at))
        end

        private

        # @param outcome [OpenLanes::Supervision::WebRebuild::Outcome]
        # @return [String]
        def text_for(outcome)
          verdict = outcome.ok? ? "The control room restarted on a rebuilt page." : "The control room restarted on its old page."
          "#{verdict} #{outcome.message.sub(/\A./, &:upcase)}."
        end
      end
    end
  end
end
