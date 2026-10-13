// The copilot conversation as the page keeps it (contract.md, "Copilot"): pure merges, so a turn that arrives twice
// (the POST's answer and the stream both carry the person's turn) is drawn once.
import type { CopilotLog, CopilotTurn, CopilotUsage } from "./types";

export const NO_USAGE: CopilotUsage = { model: null, up: 0, down: 0 };
export const EMPTY_LOG: CopilotLog = { turns: [], usage: NO_USAGE };

/**
 * Chronological order: by the server's time, then by id. Ids are ULIDs, which sort by time, and a reply's id is its
 * message's id plus a dot and its place, so within one second a message comes before its own replies.
 */
const byTime = (a: CopilotTurn, b: CopilotTurn): number =>
  a.at < b.at ? -1 : a.at > b.at ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0;

/**
 * A log from turns in any order, at most one per id: sorted, with the usage of the newest turn that carries one.
 * `fallback` is the usage when none does, which is the server's figure for turns this page has not seen.
 */
function settle(turns: Iterable<CopilotTurn>, fallback: CopilotUsage): CopilotLog {
  const sorted = [...new Map([...turns].map(t => [t.id, t])).values()].sort(byTime);
  let usage = fallback;
  for (let i = sorted.length - 1; i >= 0; i--) {
    const found = sorted[i].usage;
    if (found) {
      usage = found;
      break;
    }
  }
  return { turns: sorted, usage };
}

/** The log with `turn` in its place, unless a turn with its id is already there. */
export function withTurn(log: CopilotLog, turn: CopilotTurn): CopilotLog {
  if (log.turns.some(t => t.id === turn.id)) return log;
  return settle([...log.turns, turn], log.usage);
}

/**
 * A fetched log laid over the one already held, as one chronological union by id. The fetch holds only the newest
 * turns, so older ones the page already has stay before them, and a turn the stream delivered after the fetch left is
 * kept in its place. The header's usage comes from the newest turn that carries one, never from an older one.
 */
export function mergeLogs(held: CopilotLog | undefined, fetched: CopilotLog): CopilotLog {
  if (!held) return fetched;
  return settle([...held.turns, ...fetched.turns], fetched.usage);
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
