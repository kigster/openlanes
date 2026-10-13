// The wire contract between the engine (Ruby) and the page. Ruby's OpenLanes::Live::Snapshot builds exactly this shape,
// and spec/openlanes/live/snapshot_spec.rb checks it against web/src/api/fixtures/snapshot.json, so a field renamed on
// one side fails the other side's suite. Change both, and the fixture, together.

export type Iso = string; // ISO 8601 wall-clock time, UTC

/** One machine: this one, or another sharing the same Redis and repository (W26). */
export interface Node {
  id: string; // first 24 hex digits of SHA-256("username@hostname")
  user: string;
  host: string;
  ip: string | null;
  checkout: string; // the checkout's path, with $HOME shown as ~
  heartbeat_at: Iso;
  me: boolean;
}

export interface Station {
  key: string; // a Status key on StateMachine::SPINE, or "pr"
  label: string; // "New", "Researched", "Planning", "Building", "Building UI", "Review", "Pull request"
  agents: string[]; // agents whose `handles:` includes this station
}

export type Lane = "full" | "plan" | "quick";

export interface Status {
  key: string; // Plans::STATUSES key
  emoji: string;
  label: string;
}

export type CarState = "running" | "done" | "failed" | "stuck";
export type Phase = "calm" | "warned" | "wrap_up" | "stopped" | "expired" | null;

/** One agent working on a plan: a Board::Row. */
export interface Car {
  key: string; // "<ordinal>/<agent>", the id commands address
  agent: string;
  role: string;
  round: number;
  rounds: number;
  model: string; // full model id, e.g. "claude-sonnet-5-5"
  effort: string | null;
  state: CarState;
  phase: Phase;
  message: string; // its latest activity line
  history: string[]; // newest first, at most 50
  up: number; // tokens in
  down: number; // tokens out
  context: number | null; // tokens currently in context, when the adapter reports it
  context_limit: number | null;
  elapsed: number; // seconds
  remaining: number | null; // seconds before its timeout
  held: boolean; // a person asked it to hold for now
  // Queued by set_model for its next round, until a round runs on it. The engine always sends it;
  // optional only until src/board/sample.ts (held by another agent) adds it to sampleCar.
  next_model?: string | null;
}

export interface PullRequest {
  number: number;
  url: string;
  state: "open" | "approved" | "merged" | "closed" | "rejected";
  ci: "pending" | "passing" | "failing" | null;
  merged_at: Iso | null;
}

/** A question an agent wrote into blocked.md (B<n>), still without an answer (A<n>). */
export interface Question {
  id: string; // "<ordinal>/B<n>"
  number: number;
  heading: string;
  body: string; // Markdown
  agent: string | null; // who asked, when the ledger says
  owner: "technical" | "product"; // ⭕️ or 🅱️
  answers: string[] | null; // ["yes", "no"] when the agent declared it a yes/no question (W30)
  held: boolean; // a person chose Hold blocked
  asked_at: Iso | null;
}

export interface Plan {
  ordinal: string; // "004.00"
  title: string;
  slug: string;
  status: Status;
  lane: Lane;
  station: string; // Station.key the plan is at
  up: number;
  down: number;
  cost: number; // dollars, from the adapter's rates
  started_at: Iso | null;
  elapsed: number; // seconds this plan has been worked on, this run
  cars: Car[];
  pr: PullRequest | null;
  questions: Question[];
  interrupted: { agent: string; at: Iso; note: string } | null;
  claimed_by: string | null; // Node.id holding the claim
}

export interface LogLine {
  at: Iso;
  source: string; // "engine", "api", "redis", or an agent's name
  level: "debug" | "info" | "warn" | "error";
  text: string;
  plan: string | null;
}

export interface ModelChoice {
  id: string;
  label: string; // "Sonnet 5.5"
  rates: { in: number; out: number }; // dollars per million tokens
}

export interface Run {
  status: "running" | "wrapping_up" | "quitting" | "idle";
  started_at: Iso | null;
  up: number;
  down: number;
  cost: number;
  agents_working: number;
}

/** What the engine publishes every tick, per node. The page's whole state. */
export interface Snapshot {
  seq: number; // increases with every published snapshot from this node
  at: Iso;
  node: Node;
  repo: string; // normalised GitHub URL, "github.com/owner/name"
  project: string; // the project's name for the header (W18)
  description: string | null;
  run: Run;
  stations: Station[];
  plans: Plan[]; // plans this node is working on
  backlog: Array<Pick<Plan, "ordinal" | "title" | "status" | "lane">>; // not complete, not claimed: for "Choose an existing plan"
  models: ModelChoice[];
  autocompact: number; // fraction of the context at which agents compact, 0.4 (W28)
  log: LogLine[]; // the most recent lines, newest last
}

/** Everything the page shows: our snapshot plus every other node's, read-only. */
export interface Board {
  me: Snapshot;
  others: Snapshot[];
}

/**
 * A board as `GET /api/board` and the stream deliver it. `me` is null until this machine's engine first publishes
 * (`openlanes web` started before `openlanes run`, or the run's snapshot expired), so the page never assumes it is there.
 */
export interface WireBoard {
  me: Snapshot | null;
  others: Snapshot[];
}

export type CommandKind =
  | "answer" // payload: { question: "B2", text }
  | "hold_blocked" // payload: { question: "B2" }
  | "release_hold" // payload: { question: "B2" }
  | "resume" // after an interrupt; payload: { note? }
  | "discard" // plan-wide (W9)
  | "message" // payload: { text }
  | "hold"
  | "wrap_up"
  | "compact" // now: stopped, its session compacted with claude --resume "/compact", then carried on in it; a fresh restart when it has no session id
  | "stop"
  | "stop_all" // every agent on this node
  | "set_model" // next round; payload: { model }
  | "switch_model" // now: as compact, carried on in the new model; a fresh restart on it when the session cannot be resumed; payload: { model }
  | "add_plan" // payload: { ordinal }
  | "create_plans"; // payload: { idea }

export interface Command {
  id: string; // ULID, minted by the page; also its idempotency key
  kind: CommandKind;
  plan: string | null; // ordinal
  agent: string | null; // agent name, for commands aimed at one car
  payload: Record<string, unknown>;
}

export interface Reply {
  id: string; // the command's id
  status: "accepted" | "refused" | "done";
  reason: string | null;
  at: Iso;
}
