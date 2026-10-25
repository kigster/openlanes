# frozen_string_literal: true

module OpenLanes
  module Engine
    module Unblocking
      # A broker that ran cleanly and left an answer under its question did
      # not accept it: it asks for a), b) or c) and was told something else.
      # Left there, the page counts the question answered and hides it, and
      # the drainer never retries an answer set it already tried, so the
      # plan waits on a person who is never asked. The answer comes out and
      # the question goes back on the page, with what was said and why the
      # broker would not take it.
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
          kept = Plans::BlockedFile.reject(text, number, "> **Answer not accepted:** #{said}\n>\n> #{refused.why}") || text
          UI.log("answer to B#{number} not accepted: #{refused.why}", level: :warn, plan: refused.ordinal)
          kept
        end

        # What the broker wrote in its journal during this drain, last line
        # first, since that is where it says what it did with the answers.
        #
        # @return [String]
        def refusal(drain, subject)
          rounds = Plans::PlanState.for(subject.feature.path).journal(drain.agent).drop(drain.rounds.to_i)
          said = rounds.flat_map(&:entries).last&.text
          said ? "#{drain.agent}: #{Plans::Journal.clip(said)}" : "#{drain.agent} left it unfolded and said nothing"
        rescue OpenLanes::Error, JSON::ParserError
          "#{drain.agent} left it unfolded"
        end
      end
    end
  end
end
