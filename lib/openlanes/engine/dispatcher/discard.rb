# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # A plan a person is throwing back (W9): its agents stopping, then its
      # worktree reset and its folder moved back to the state their work
      # started from. {Live::Commands} holds on to it and replies once
      # {#finished?}.
      #
      # @!attribute [r] ordinal
      #   @return [String]
      # @!attribute [r] status
      #   @return [String, nil] "done" or "refused", once it is over
      # @!attribute [r] reason
      #   @return [String, nil]
      # @!attribute [r] from
      #   @return [Symbol, nil] the state the stopped agents started from,
      #     nil when none was running, which means one step back
      Discard = Struct.new(:ordinal, :status, :reason, :from) do
        # @return [Boolean]
        def finished? = !status.nil?
      end
    end
  end
end
