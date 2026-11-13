# frozen_string_literal: true

module OpenLanes
  module Web
    class Demo
      # The unblocker's interview under `--demo`, where no agent runs: two
      # canned questions, then a decision built from what the person said,
      # so the page and Cypress walk the whole interview without a model.
      module Interview
        # The canned questions, in the order they are asked.
        QUESTIONS = [
          { text:    "Should the plan go ahead with the approach it proposed, or wait for a different one?",
            options: [{ label: "Go ahead with the proposed approach", recommended: true },
                      { label: "Wait for a different approach", recommended: false }] },
          { text:    "Is there anything the agents must keep in mind while they build it?",
            options: [{ label: "Nothing more, keep it simple", recommended: true },
                      { label: "Keep the existing behaviour unchanged", recommended: false }] }
        ].freeze

        # @param interview [OpenLanes::Live::Interview]
        # @return [Array<OpenLanes::Live::Interview::Turn>]
        def self.call(interview)
          history = interview.history
          said = history.select { it.from == "you" }.map(&:text)
          turn = Live::Interview::Turn
          if said.size < QUESTIONS.size
            [turn.new(id: interview.next_id, from: "unblocker", kind: "question", **QUESTIONS[said.size])]
          else
            answer = said.join("; ")
            [turn.new(id: interview.next_id, from: "unblocker", kind: "decision", text: "Here is what I understood: #{answer}. Is that right?", answer:)]
          end
        end
      end
    end
  end
end
