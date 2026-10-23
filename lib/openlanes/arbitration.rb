# frozen_string_literal: true

module OpenLanes
  # `obi-wan-kenobi-arbitrator` (M7, M8, M9): a read-only agent that rules on
  # the rejection cap, appeals, luke-versus-rey disputes and `review-passed`
  # verdicts. The agent only answers with a `ruling` block; reading that
  # block, counting rejections and acting on a ruling live here, so the
  # agent never needs a write tool.
  module Arbitration
    # The agent's name, as `agents/obi-wan-kenobi-arbitrator.md` spells it.
    AGENT = "obi-wan-kenobi-arbitrator"

    module_function

    # @param text [String] the adapter's final text
    # @return [OpenLanes::Arbitration::Ruling]
    def ruling(text) = Ruling.parse(text)

    # @param agents [OpenLanes::Agents::Registry] whose rejections count
    # @return [OpenLanes::Arbitration::Counter]
    def counter(agents:) = Counter.new(agents:)
  end
end
