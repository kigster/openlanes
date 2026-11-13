# frozen_string_literal: true

module OpenLanes
  module Engine
    module Unblocking
      # A broker that ran cleanly and left an answer under its question could
      # not read a decision out of it. Left there, the page counts the
      # question answered and hides it, and the drainer never retries an
      # answer set it already tried, so the plan waits on a person who is
      # never asked. The answer comes out and the question goes back on the
      # page, with what was said and the broker's follow-up question.
      #
      # It is worded as a follow-up, never as a rejection: the broker has no
      # standing to refuse a person, and "Answer not accepted" over a note
      # the broker had written to itself read as exactly that.
      class Reopener
        # What one drain's refusals share: the plan, why, and what was answered.
        Refused = Data.define(:ordinal, :why, :answers)

        # @param drain [Drain]
        # @param outcome [Lifecycle::Unblocker::Outcome]
        # @return [void]
        def call(drain, outcome)
          path = File.join(outcome.subject.feature.path, "blocked.md")
          text = File.read(path)
          refused = Refused.new(ordinal: drain.ordinal, why: refusal(drain, outcome.subject), answers: Plans::BlockedFile.answers(text))
          File.write(path, outcome.waiting.reduce(text) { |kept, question| reject(kept, question.number, refused) })
        rescue SystemCallError => e
          UI.log("could not reopen the unaccepted answers: #{e.message}", level: :warn, plan: drain.ordinal)
        end

        private

        # @return [String] +text+ with one question's answer taken out
        def reject(text, number, refused)
          said = Plans::Journal.clip(refused.answers[number].to_s.gsub(/<!--.*?-->|^Answered by .*$/, "").split.join(" "))
          kept = Plans::BlockedFile.reject(text, number, "> **You answered:** #{said}\n>\n> #{refused.why}") || text
          UI.log("answer to B#{number} needs a follow-up: #{refused.why}", level: :warn, plan: refused.ordinal)
          kept
        end

        # The broker's follow-up: the last line it wrote in its journal during
        # this drain, which its definition tells it to write as a question to
        # the person. A silent broker still leaves them something to answer.
        #
        # @return [String]
        def refusal(drain, subject)
          rounds = Plans::PlanState.for(subject.feature.path).journal(drain.agent).drop(drain.rounds.to_i)
          said = rounds.flat_map(&:entries).last&.text
          said ? "**#{drain.agent} asks:** #{Plans::Journal.clip(said)}" : unclear(drain)
        rescue OpenLanes::Error, JSON::ParserError
          unclear(drain)
        end

        # @return [String] what the card says when the broker asked nothing itself
        def unclear(drain)
          "**#{drain.agent} asks:** I could not tell what you decided. Which of the options below should happen, or what should happen instead?"
        end
      end
    end
  end
end
