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
          said = interview.history.select { it.from == "you" }.map(&:text)
          return [question(interview, QUESTIONS[said.size])] if said.size < QUESTIONS.size

          [decision(interview, said.join("; "))]
        end

        # @return [OpenLanes::Live::Interview::Turn]
        def self.question(interview, asked) = Live::Interview::Turn.new(id: interview.next_id, from: "unblocker", kind: "question", **asked)

        # The person's words go in `answer` only, which the panel shows as the
        # answer to confirm; `text` stays the unblocker's own, so a label the
        # person typed is not refused as the unblocker's (F3).
        #
        # @return [OpenLanes::Live::Interview::Turn]
        def self.decision(interview, answer)
          Live::Interview::Turn.new(id: interview.next_id,
            from: "unblocker",
            kind: "decision",
            text: "Here is what I understood from your answers. Is that right?",
            answer:)
        end
      end
    end
  end
end
