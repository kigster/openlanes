# frozen_string_literal: true

module OpenLanes
  module Arbitration
    # A builder's appeal against one of staff-reviewer's findings, written as a
    # signature note (M8 says "in the ledger"):
    # `--note "appeal: F2 because the spec rules that test out"`.
    Appeal = Data.define(:finding, :reason) do
      # The note's shape. A note without a reason is not an appeal: the
      # arbitrator would have nothing to weigh.
      self::NOTE = /\Aappeal:\s*(F\d+)\s+because\s+(\S.*)\z/im

      # @param note [String, nil] a signature's note
      # @return [Appeal, nil] nil when the note is not an appeal
      def self.parse(note)
        match = note.to_s.strip.match(self::NOTE) or return nil
        new(finding: match[1].upcase, reason: match[2].strip)
      end
    end
  end
end
