# frozen_string_literal: true

RSpec.describe OpenLanes::Events::LessonUsage do
  def lesson(kind, id, plan:, **seen)
    OpenLanes::Events::Event.new(event_id: id,
      kind:,
      at: Time.iso8601(seen.fetch(:at, "2026-11-12T12:00:00Z")),
      project: seen.fetch(:project, "demo"),
      plan:,
      agent: "backend-coder",
      payload: { "round" => seen.fetch(:round, 1), "lesson" => seen.fetch(:lesson) })
  end

  let(:events) do
    [lesson("lesson_offered", "a", plan: "061.00", lesson: "L-0007"),
     lesson("lesson_offered", "b", plan: "061.00", lesson: "L-0007", round: 2),
     lesson("lesson_offered", "c", plan: "062.00", lesson: "L-0007"),
     lesson("lesson_cited", "d", plan: "062.00", lesson: "L-0007", at: "2026-11-14T09:00:00Z"),
     lesson("lesson_cited", "e", plan: "061.00", lesson: "L-0007", at: "2026-11-13T09:00:00Z"),
     lesson("lesson_offered", "f", plan: "062.00", lesson: "L-0012"),
     lesson("lesson_offered", "g", plan: "061.00", lesson: "L-0012", project: "other"),
     OpenLanes::Events::Event.new(event_id: "h", kind: "agent_started", at: Time.now, plan: "062.00", payload: { "round" => 1 })]
  end

  it "counts distinct plans, not invocations, and keeps the latest citation" do
    usage = described_class.tally(events)

    expect(usage["L-0007"]).to have_attributes(offered: 2, cited: 2, last_cited: "2026-11-14T09:00:00.000Z")
  end

  it "tells one project's plan from another's with the same ordinal" do
    expect(described_class.tally(events)["L-0012"]).to have_attributes(offered: 2, cited: 0, last_cited: nil)
  end

  it "counts only the named project's events when asked" do
    expect(OpenLanes::Events.lesson_usage(events, project: "demo")["L-0012"]).to have_attributes(offered: 1)
  end

  it "reads a lesson the log never saw as unseen, not as missing" do
    expect(described_class.unseen("L-0099")).to have_attributes(offered: 0, cited: 0, last_cited: nil)
  end
end
