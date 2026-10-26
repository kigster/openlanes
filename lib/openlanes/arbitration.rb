# frozen_string_literal: true

module OpenLanes
  # `arbitrator` (M7, M8, M9): a read-only agent that rules on
  # the rejection cap, appeals, backend-coder-versus-frontend-coder disputes and
  # `review-ok-not-perfect` verdicts at `mvp`. The agent only answers with a
  # `ruling` block; reading that block, counting rejections and acting on a
  # ruling live here, so the agent never needs a write tool.
  module Arbitration
    # The agent's name, as `agents/arbitrator.md` spells it.
    AGENT = Agents::Names::ARBITRATOR

    module_function

    # @param text [String] the adapter's final text
    # @return [OpenLanes::Arbitration::Ruling]
    def ruling(text) = Ruling.parse(text)

    # @param agents [OpenLanes::Agents::Registry] whose rejections count
    # @return [OpenLanes::Arbitration::Counter]
    def counter(agents:) = Counter.new(agents:)

    # Send a plan to ⭕️ with +markdown+ as its `blocked.md`. ⭕️'s invariant
    # asks for the open question before the machine lets the plan in, so the
    # file is written first; but only where the topology has the edge, and
    # it is taken back when the move is refused, so a refusal never leaves a
    # stray `blocked.md` on a plan that is not blocked.
    #
    # @param subject [OpenLanes::Plans::Subject] the plan as it stands now
    # @param markdown [String]
    # @return [Boolean] whether the plan reached ⭕️
    def block(subject, markdown)
      return false unless Plans::StateMachine.edge?(subject.status.key, :blocked)

      path = File.join(subject.feature.path, "blocked.md")
      before = File.exist?(path) ? File.read(path) : nil
      File.write(path, markdown)
      begin
        subject.machine.promote!(:blocked)
        true
      rescue Plans::StateMachine::Refused
        before ? File.write(path, before) : FileUtils.rm_f(path)
        false
      end
    end
  end
end
