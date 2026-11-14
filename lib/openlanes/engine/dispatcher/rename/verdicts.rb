# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # What a closing note rules, and where that sends the folder.
        module Verdicts
          module_function

          # @param entry [OpenLanes::Plans::Ledger::Entry]
          # @return [Symbol, nil] :rejected, :verified, :approved, :slop, :product or nil
          def of(entry)
            note = entry.note.to_s.downcase
            # Anchored, as the rejection count is: "nothing to reject" approves.
            return :rejected if note.strip.match?(Verification::Outcome::REJECTION)
            return :verified if note.include?("verified")
            return :approved if note.include?("approv")
            return :slop if note.include?("slop") || note.include?("rewrite")

            :product if note.include?("product")
          end

          # @param partner_running [Boolean] whether another agent is in the plan
          # @return [Symbol, nil] where the folder goes
          def target(agent, verdict, partner_running)
            case verdict
            when :rejected then :rejected
            when :slop then :rewrite
            else partner_running ? agent.holds_at : agent.advances_to
            end
          end
        end
      end
    end
  end
end
