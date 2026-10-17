// Builders over the fixture for tests: a Board, and plans and cars with only the fields a test cares about changed.
import type { Board, Car, LastKnown, Plan, PullRequest, Question } from "../api/types";
import { loadFixtureBoard } from "../api/client";

export const sampleBoard = (): Board => loadFixtureBoard();

export function sampleCar(over: Partial<Car> = {}): Car {
  const agent = over.agent ?? "luke-backend";
  return {
    key: `001.00/${agent}`,
    agent,
    role: "builder",
    round: 1,
    rounds: 2,
    model: "claude-opus-5-5",
    effort: "high",
    state: "running",
    phase: "calm",
    message: "Editing lib/openlanes/engine/dispatcher.rb",
    history: [],
    up: 1200,
    down: 80,
    context: null,
    context_limit: null,
    elapsed: 75,
    remaining: null,
    held: false,
    subagents: 0,
    ...over,
  };
}

export function samplePr(over: Partial<PullRequest> = {}): PullRequest {
  return { number: 44, url: "https://github.com/example-org/example-repo/pull/44", state: "open", ci: "pending", merged_at: null, ...over };
}

export function sampleQuestion(over: Partial<Question> = {}): Question {
  return {
    id: "001.00/B1",
    number: 1,
    heading: "B1 Redis key layout",
    body: "Should Redis keys carry the checkout path?",
    agent: "luke-backend",
    owner: "technical",
    options: null,
    held: false,
    asked_at: null,
    ...over,
  };
}

export function sampleLastKnown(over: Partial<LastKnown> = {}): LastKnown {
  return {
    agent: "rey-frontend",
    source: "agent",
    at: "2026-10-13T08:58:00Z",
    round: 1,
    status: "Interrupted",
    next_step: "draw the panel",
    note: null,
    ...over,
  };
}

export function samplePlan(over: Partial<Plan> = {}): Plan {
  return {
    ordinal: "001.00",
    title: "Clean agent boundaries",
    slug: "clean-agent-boundaries",
    status: { key: "building", emoji: "🟡", label: "Building" },
    lane: "full",
    station: "building",
    up: 5000,
    down: 300,
    cost: 1.5,
    started_at: null,
    elapsed: 125,
    cars: [sampleCar()],
    pr: null,
    questions: [],
    interrupted: null,
    claimed_by: null,
    unacked: 0,
    last_known: [],
    locked: null,
    ...over,
  };
}
