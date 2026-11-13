# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    class Interview
      # What the unblocker reads for one turn of an interview (plan 068):
      # the rules, the open question as `blocked.md` asks it, the plan's
      # spec and plan, and the conversation so far. The whole conversation
      # goes in every time, so no `claude` session has to be kept per question.
      class Brief
        # How the unblocker conducts the interview, and the one shape it answers in.
        RULES = <<~RULES
          You are interviewing a person to settle one open question that blocks a plan. Follow these rules:

          - Ask one question at a time, each with 2 to 5 short options and exactly one recommended.
          - Never reject or refuse what the person says. When a reply is unclear, ask a clarifying
            question, or say back what you understood and ask for a yes.
          - Every question stands alone in plain words. Never use bare labels such as B2, A9, U3 or D1:
            say what the thing is.
          - When the decision is clear, finish with exactly one `decision` turn: `text` says back the
            decision and asks the person to confirm it, `answer` is the answer to write, in plain words.

          Reply with JSON only: {"turns": [{"kind": "text" | "question" | "decision", "text": String,
          "options": [{"label": String, "recommended": Boolean}] (question only), "answer": String (decision only)}]}
        RULES

        # @param question [String] the open question's section of `blocked.md`
        # @param history [Array<OpenLanes::Live::Interview::Turn>]
        # @param documents [Hash{String => String}] file name to its text, e.g. spec.md
        # @param rephrase [String, nil] why the last reply could not be shown
        def initialize(question:, history:, documents: {}, rephrase: nil)
          @question = question
          @history = history
          @documents = documents
          @rephrase = rephrase
        end

        # @return [String]
        def to_s = [RULES, question, *documents, conversation, rephrase].compact.join("\n\n")

        private

        # @return [String]
        def question = "## The open question\n\n#{@question.strip}"

        # @return [Array<String>]
        def documents = @documents.map { |name, text| "## #{name}\n\n#{text.strip}" }

        # @return [String]
        def conversation
          return "## The conversation so far\n\nNothing yet: open the interview with your first question." if @history.empty?

          "## The conversation so far\n\n#{@history.map { "#{it.from}: #{JSON.generate(it.wire.except(:id, :at, :from))}" }.join("\n")}"
        end

        # @return [String, nil]
        def rephrase = @rephrase && "## Rephrase\n\nYour last reply could not be shown (#{@rephrase}). Say it again, following the rules."
      end
    end
  end
end
