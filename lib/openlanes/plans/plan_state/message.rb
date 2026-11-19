# frozen_string_literal: true

require "securerandom"

module OpenLanes
  module Plans
    class PlanState
      # One message as {PlanState#message!} receives it. +after+ is the
      # numbers already taken elsewhere (mailbox.md); +command+ the id of the
      # page's command that sent it, applied at least once (W13).
      Message = Data.define(:from, :to, :body, :at, :after, :command) do
        # @param at [Time]
        # @param after [Integer]
        # @param command [String, nil]
        def initialize(at: Time.now, after: 0, command: nil, **) = super

        # The id, not the number, is what a drain dedupes on: a worktree's
        # copy of the file numbers its messages independently of the main
        # checkout's, so two different messages can both be #4.
        #
        # @param number [Integer]
        # @return [Hash] in the key order `state.json` has always carried
        def to_json_h(number)
          record = { "id" => SecureRandom.uuid, "number" => number, "at" => at.iso8601, "from" => from, "to" => to,
                     "body" => body, "read" => "no" }
          record["command"] = command if command
          record
        end
      end
    end
  end
end
