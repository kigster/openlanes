# frozen_string_literal: true

# Every writer of `state.json`, through the PlanState facade, at fixed times.
# Run against the code before the split to record `state.json` beside this
# file, and by plan_state_split_integration_spec.rb against the code after it.
# rubocop:disable-next Metrics/MethodLength -- a script of writer calls, one per line, read top to bottom
module PlanStateSplitDrive
  AT = Time.utc(2026, 11, 17, 9, 0, 0)

  module_function

  # @param state [OpenLanes::Plans::PlanState]
  # @return [Hash] the document, with what varies per run normalised
  def call(state)
    harness(state)
    agents(state)
    engine(state)
    normalise(state.read)
  end

  def harness(state)
    state.stage!(agent: "backend-coder",
      round: 1,
      reset: true,
      status: "Started",
      from: "planned",
      started_at: AT.iso8601,
      adapter: "claude",
      session: "s1",
      cwd: "/repo")
    state.state!(:building)
    state.stage!(agent: "backend-coder", round: 1, status: "Completed", to: "building", finished_at: (AT + 60).iso8601)
    state.resume_anyway!(till: AT + 86_400)
    state.take_global_lock!(at: AT)
  end

  def agents(state)
    state.sign!(agent: "backend-coder", round: 1, status: "Started", at: AT)
    state.sign!(agent: "backend-coder", round: 1, status: "Completed", note: "done", next_agent: "staff-reviewer", at: AT + 60)
    state.message!(from: "backend-coder", to: "frontend-coder", body: "hi", at: AT, after: 2, command: "c1")
    state.message!(from: "backend-coder", to: "frontend-coder", body: "hi", at: AT, command: "c1")
    state.ack!(3, by: "frontend-coder")
    state.deliver!({ "id" => "fixed", "number" => 3, "at" => AT.iso8601, "from" => "a", "to" => "b", "body" => "x" },
      reserved: [1])
    state.record_last_known("backend-coder",
      OpenLanes::Plans::LastKnownState.new(source: "agent",
        round: 1,
        status: "Interrupted",
        at: AT,
        done: ["A"],
        remaining: ["B"],
        next_step: "B",
        files_touched: ["a.rb"]))
  end

  def engine(state)
    state.rule!(kind: "appeal",
      pr: 9,
      round: "2",
      outcome: "struck",
      findings: { struck: ["F1"], headings: { F1: "Bad" } },
      winner: nil,
      reason: "r",
      trigger: "t",
      review: 1,
      at: AT)
    state.finish!("approved", at: AT)
    state.journal!(agent: "backend-coder",
      entries: [OpenLanes::Plans::Journal::Entry.new(kind: "note", text: "n")],
      round: 1,
      state: :building)
    state.hold!(agent: "backend-coder", session: "s1")
    state.answer!(agent: "backend-coder", ref: "B1", question: "Q", answer: "a")
    state.conversion!(question: 1, digest: "d", original: "o", model: "m", outcome: "rejected", note: "why", at: AT)
    state.assess!({ 9 => "low" }, at: AT)
    state.rebased!(10, at: AT)
    extensions(state)
  end

  def extensions(state)
    state.ask_extension!(agent: "backend-coder", state: :building, round: 1, limit: "time", at: AT, stage: "estimate")
    state.estimate_extension!(agent: "backend-coder", seconds: 600, why: "w", at: AT)
    state.settle_extension!(1, at: AT, answer: "yes", by: "operator", grant: "time", seconds: 600)
    state.amend_extension!(1, seconds: 300)
    state.spend_extension!(1)
    state.ask_quality!(at: AT)
    state.settle_quality_ask!(answer: "mvp", by: "operator", at: AT)
  end

  def normalise(data)
    data["messages"].each { it["id"] = "uuid" unless it["id"] == "fixed" }
    data.merge("updated_at" => "normalised")
  end
end
