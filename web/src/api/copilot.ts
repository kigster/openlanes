// The copilot conversation as the page keeps it (contract.md, "Copilot"): pure merges, so a turn that arrives twice
// (the POST's answer and the stream both carry the person's turn) is drawn once.
import type { CopilotLog, CopilotTurn, CopilotUsage } from "./types";

export const NO_USAGE: CopilotUsage = { model: null, up: 0, down: 0 };
export const EMPTY_LOG: CopilotLog = { turns: [], usage: NO_USAGE };

/** The log with `turn` added at the end, unless a turn with its id is already there. A reply's usage becomes the log's. */
export function withTurn(log: CopilotLog, turn: CopilotTurn): CopilotLog {
  if (log.turns.some(t => t.id === turn.id)) return log;
  return { turns: [...log.turns, turn], usage: turn.usage ?? log.usage };
}

/**
 * A fetched log laid over the one already held: the fetched turns, then any the stream delivered that the fetch had
 * not seen yet, so a GET that left before an event and landed after it never drops that event's turn.
 */
export function mergeLogs(held: CopilotLog | undefined, fetched: CopilotLog): CopilotLog {
  if (!held) return fetched;
  return held.turns.reduce(withTurn, fetched);
}

/** Whether `turn` answers the message with id `message`. */
export const answers = (turn: CopilotTurn, message: string): boolean => turn.from === "copilot" && turn.id.startsWith(`${message}.`);

/**
 * Accepts whatever `GET /api/copilot` answered as a log, so a server that predates the copilot (or a test double that
 * answers every GET with a board) leaves the panel empty rather than broken.
 */
export function asLog(data: unknown): CopilotLog {
  const log = data as Partial<CopilotLog> | null;
  return Array.isArray(log?.turns) ? { turns: log.turns, usage: log.usage ?? NO_USAGE } : EMPTY_LOG;
}
