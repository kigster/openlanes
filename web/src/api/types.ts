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

export type Starts = "research" | "planning" | "building";

export interface Status {
  key: string; // Plans::STATUSES key
  emoji: string;
  label: string;
  note: string; // what the state means, for a tooltip
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
  // Its sub-agents running right now, by name (Task's subagent_type, else its description), oldest first. Empty
  // when it has none, and always for an adapter whose stream never says (codex, pi).
  subagents: string[];
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

/** One choice a question offers (D3), as Plans::Choices read it. A yes/no question is a) yes, b) no. */
export interface QuestionOption {
  letter: string; // "a", "b", …
  label: string; // the option, its recommended marker stripped
  recommended: boolean; // at most one per question
  answer: string; // what choosing it sends: "a) <label>", or the bare "yes" / "no"
}

/**
 * A request still without an answer: a question an agent wrote into blocked.md (B<n>, answered by A<n>), or the
 * harness asking for more time or another round for an agent that ran out (X<n>, E1), which offers only its options.
 */
export interface Question {
  id: string; // "<ordinal>/B<n>", "<ordinal>/X<n>" or "<ordinal>/Q1"
  number: number;
  kind: "block" | "extension" | "quality"; // quality: R4's desired_codebase_quality, asked once per project
  heading: string;
  body: string; // Markdown
  agent: string | null; // who asked, when the ledger says
  owner: "technical" | "product"; // ⭕ or 🛑
  options: QuestionOption[] | null; // what the question offers to choose from (D3); null when it wants words
  held: boolean; // a person chose Hold blocked
  asked_at: Iso | null;
}

/**
 * Where one agent stood when its round ended early (LastKnownState in Ruby): its own `state resume` record, or the
 * harness's when it died first. Shown to a person; never an input to anything on the page.
 */
export interface LastKnown {
  agent: string;
  source: "agent" | "harness";
  at: Iso;
  round: number;
  status: string; // a ledger status: "Interrupted", "Needs input", ...
  next_step: string | null;
  note: string | null;
}

/**
 * A plan whose pull request was approved or merged during this run. The engine keeps sending it for the rest of the
 * run, so its row stays on the board at half height; after a restart it sends only the most recent one.
 */
export interface Finished {
  kind: "approved" | "merged"; // matches pr.state: "approved", or "merged" with merged_at set
  at: Iso;
}

/** Messages one agent sent another that the recipient has not acked yet. */
export interface UnackedMail {
  from: string;
  to: string;
  count: number;
  since: string; // the oldest one's timestamp, as the mailbox wrote it
}

/** The latest arbitration ruling on a plan, as the live snapshot carries it (contract.md, `ruling`). */
export interface Ruling {
  at: Iso;
  kind: "cap" | "appeal" | "dispute" | "passed_check";
  pr: number | null;
  round: number | null;
  outcome: string; // cap: go|no_go; appeal: upheld|struck; dispute: the winner; passed_check: fair|too_harsh|too_lenient
  findings: { struck: string[]; critical: string[]; headings?: Record<string, string> }; // headings: a struck id's heading
  winner: string | null;
  reason: string;
  trigger: string;
  review?: number; // the round of staff-reviewer's review the ids belong to
}

export interface Plan {
  ordinal: string; // "004.00"
  title: string;
  slug: string;
  summary: string; // spec.md's first paragraph of prose, "" when it has none
  status: Status;
  starts: Starts;
  group: string; // lowest ordinal of its depends_on group; plans in no group name themselves
  station: string; // Station.key the plan is at
  up: number;
  down: number;
  cost: number; // dollars, from the adapter's rates
  started_at: Iso | null;
  elapsed: number; // seconds this plan has been worked on, this run
  cars: Car[];
  pr: PullRequest | null;
  finished: Finished | null; // null until its pull request is approved or merged
  questions: Question[];
  interrupted: { agent: string; at: Iso; note: string } | null;
  claimed_by: string | null; // Node.id holding the claim
  unacked: number; // mailbox messages nobody has acked; a warning only (D2)
  rejections?: { count: number; max: number }; // reviewer rejections so far, against merge.max_rejections
  ruling?: Ruling | null; // the arbitrator's latest ruling, null when there is none
  arbitrating?: boolean; // the arbitrator is on this plan now
  mail: UnackedMail[]; // the unacked messages, one per sender and recipient, oldest first
  last_known: LastKnown[]; // one per agent with a resume record, empty when none
  locked: { pid: number; host: string; started_at: Iso; foreign: boolean } | null; // the plan's lock, alive or not; foreign: held by another machine
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
  rates: { in: number; out: number } | null; // dollars per million tokens; null for a model nobody has priced
}

/** What one coding CLI can do, as its adapter declares it. */
export interface AdapterCapabilities {
  compacts: boolean;
  resumes: boolean;
  enforces_tool_denial: boolean;
}

/** Whether one coding CLI can take an agent on this node right now, as its probe last found it (plan 040, D5). */
export interface AdapterAvailability {
  name: string; // "claude", "codex", "pi"
  available: boolean | null; // null until the first probe has answered
  reason: string | null; // why it is not available, for a person; null when it is
  models: ModelChoice[]; // most capable first; [] when not available
  checked_at: Iso | null;
  capabilities: AdapterCapabilities;
}

/** Set once the engine has recovered from a Redis outage this run (plan 022); absent or null otherwise. */
export interface Outage {
  started_at: Iso;
  ended_at: Iso;
  seconds: number;
  measured_by: "heartbeat" | "clock";
  reconciled_from: "redis" | "file" | null;
}

export interface Run {
  status: "running" | "wrapping_up" | "quitting" | "idle";
  started_at: Iso | null;
  up: number;
  down: number;
  cost: number;
  agents_working: number;
  jobs: number; // the run's concurrency limit, changed live by /concurrency
  outage?: Outage | null; // optional: an engine older than plan 022 never sends it
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
  backlog: Array<Pick<Plan, "ordinal" | "title" | "status" | "starts">>; // not complete, not claimed: for "Choose an existing plan"
  adapters: AdapterAvailability[]; // every adapter, in the engine's order (plan 040, D9)
  autocompact: number; // fraction of the context at which agents compact, 0.4 (W28)
  redis_url: string | null; // the Redis the engine keeps claims and run state in, userinfo redacted to ":***"
  log: LogLine[]; // the most recent lines, newest last
  bombs: Bomb[]; // plans halted on a 💣 question on this node, [] when none (plan 009)
}

/** A plan that sat blocked past its deadline: halted until someone responds, discusses, or resumes it anyway. */
export interface Bomb {
  plan: string; // ordinal
  slug: string;
  blocked_md: string; // blocked.md, Markdown
  blocked_since: Iso;
  resume_until: Iso | null; // set by resume_anyway: the halt is lifted until then
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
  | "create_plans" // payload: { idea }
  | "respond" // a 💣 plan: answers its first open question in blocked.md; payload: { text }
  | "pause_discuss" // a 💣 plan: holds its running agents while the person talks it over with the copilot
  | "resume_anyway" // a 💣 plan: lifts the halt for 24 h
  | "stop_plan" // /stop: signals the plan's agents and takes it off the board; payload: {}
  | "restart_plan" // /restart: puts an idle plan back on the board; refused while it has an agent
  | "set_concurrency"; // /concurrency: payload: { limit }, never kills a running agent

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

/** The copilot's model and running token totals (W17), shown in its header like a car's. */
export interface CopilotUsage {
  model: string | null; // null until the copilot has run
  up: number;
  down: number;
}

interface TurnBase {
  id: string; // the message's ULID; a reply's is that id, a dot and its place: "01J….1"
  text: string;
  at: Iso;
}

/** What the person said. */
export interface YouTurn extends TurnBase {
  from: "you";
  kind: "text";
  usage: null;
}

/** What the copilot said: words, a red card to confirm a command that cannot be undone, or a drafted answer. */
export type CopilotReply = TurnBase & { from: "copilot"; usage: CopilotUsage | null } & (
    | { kind: "text" }
    | { kind: "confirm"; command: Omit<Command, "id">; confirm: string; done: string } // confirm: the button; done: what the card says once accepted
    | { kind: "draft"; question: string; draft: string } // question: a Question.id, whose answer box the draft goes into
  );

/** One turn of the conversation, as `GET /api/copilot` and `event: copilot` deliver it. */
export type CopilotTurn = YouTurn | CopilotReply;

/** `GET /api/copilot`: the newest turns, oldest first, and the copilot's latest usage. */
export interface CopilotLog {
  turns: CopilotTurn[];
  usage: CopilotUsage;
}

/** `POST /api/copilot`'s body. */
export interface CopilotMessage {
  id: string;
  text: string;
}

/** One page in a chat between machines (plan 006): `id` is the page's own, kept in its session storage. */
export interface ChatParticipant {
  id: string;
  name: string; // what the person typed in the Name dialog
  machine: string; // the Node.id of the machine the page is on
  label: string; // that machine's "user@host"
  idle: boolean; // 60 s without touching the chat (D7)
}

/** An invite to a chat, open to every page on the invited machine until one answers or 60 s pass (D9). */
export interface ChatInvite {
  id: string; // UUID
  chat: string; // the chat's UUID
  from: ChatParticipant;
  machine: string; // the invited Node.id
  label: string; // the invited machine's "user@host"
  expires_at: Iso;
}

/** An invite this page sent and is still waiting on. */
export interface ChatOutgoing {
  id: string;
  machine: string;
  label: string;
}

/** `GET /api/chat?page=`: the chat this page is in, the invites open to its machine, the ones it waits on. */
export interface ChatState {
  chat: { id: string; me: ChatParticipant; participants: ChatParticipant[] } | null;
  invites: ChatInvite[];
  outgoing: ChatOutgoing[];
}

/** `event: chat` on the page's stream. Nothing is stored (D2): what is missed is gone. */
export type ChatEvent =
  | { kind: "joined" | "left" | "idle" | "back"; chat: string; who: ChatParticipant; participants: ChatParticipant[] }
  | { kind: "roster"; chat: string; participants: ChatParticipant[] }
  | { kind: "said"; chat: string; who: ChatParticipant; id: string; text: string; at: Iso }
  | { kind: "invited"; invite: ChatInvite }
  | { kind: "invite_closed"; invite: string; answer: "accepted" | "declined" | "expired" }
  | { kind: "declined" | "unanswered"; invite: string; machine: string; label: string };

/** What `POST /api/chat/say` answers: the message as sent. */
export interface ChatSaid {
  id: string;
  text: string;
  at: Iso;
  who: ChatParticipant;
}

// The app a plan builds, run by `openlanes project start` (plan 012). Ruby's OpenLanes::Apps::Status#to_h builds exactly
// this shape, and spec/openlanes/apps/status_spec.rb pins it.

export type AppState = "starting" | "ready" | "restarting" | "stopped" | "failed";

/** One process of a running app: `event: app`, or one entry of `event: apps`. */
export interface AppStatus {
  plan: string; // "012.00"
  branch: string;
  process: string; // its name in `.openlanes.yml` app.processes
  state: AppState;
  port: number;
  preview: boolean; // the process the Preview tab shows
  url: string; // "http://127.0.0.1:<port>/"
  framing: "frame" | "window" | null; // set on the preview process once it is ready
  reason: string | null; // why it failed
  at: Iso;
}

/** What the Preview tab's toolbar asks of the runner: `POST /api/apps/commands`. */
export interface AppCommand {
  plan: string;
  action: "restart" | "stop";
  target?: string | null; // "backend" (every process but the previewed one), a process name, or every process
}
