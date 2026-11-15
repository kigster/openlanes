// The unblocker's interview as the page keeps it: pure merges, so a turn that arrives twice (the POST's answer and the
// stream both carry the person's turn) is drawn once. The wire calls live here too, beside the shapes they carry.
import { ulid } from "ulid";
import { ApiError, mintCommand, postCommand, postJson } from "./client";
import type { Command, InterviewTurn, Reply } from "./types";

/** Where one question's conversation lives. */
export const interviewPath = (plan: string, number: number): string => `/api/plans/${encodeURIComponent(plan)}/questions/${number}/interview`;

/** The cache key of one question's conversation. */
export const interviewKey = (plan: string, number: number) => ["interview", plan, number] as const;

/** A stream id as two numbers. One that is missing or malformed reads as zero, so it sorts first and never throws. */
const place = (seq: string | undefined): [number, number] => {
  const [ms, n] = (seq ?? "").split("-").map(Number);
  return [ms || 0, n || 0];
};

/**
 * The server's order, and only that. Sorting by `at` and then `id` drew a reply of two turns in either order, since
 * both carry one second and random ids, and when the words sorted after the question or the decision, the buttons
 * were not drawn at all (issue 252). Compared as numbers: as text, "9-0" would sort after "10-0".
 */
const bySeq = (a: InterviewTurn, b: InterviewTurn): number => {
  const [ams, an] = place(a.seq);
  const [bms, bn] = place(b.seq);
  return ams - bms || an - bn;
};

/** Turns in any order, at most one per id (the first seen wins), in the order the server stored them. */
export function settle(turns: Iterable<InterviewTurn>): InterviewTurn[] {
  const unique = new Map<string, InterviewTurn>();
  for (const turn of turns) if (!unique.has(turn.id)) unique.set(turn.id, turn);
  return [...unique.values()].sort(bySeq);
}

/** The turns with `turn` in its place, unless one with its id is there already. */
export function withTurn(turns: InterviewTurn[], turn: InterviewTurn): InterviewTurn[] {
  return turns.some(t => t.id === turn.id) ? turns : settle([...turns, turn]);
}

/** A fetched history laid over the held turns: the union by id, so a turn the stream delivered meanwhile stays. */
export function mergeTurns(held: InterviewTurn[] | undefined, fetched: InterviewTurn[]): InterviewTurn[] {
  return settle([...(held ?? []), ...fetched]);
}

/** The decision the unblocker is waiting on a yes for: the newest turn, when it is one. */
export function pendingDecision(turns: InterviewTurn[]): InterviewTurn | null {
  const last = turns.at(-1);
  return last?.from === "unblocker" && last.kind === "decision" ? last : null;
}

/** The question the unblocker is waiting on an answer to: the newest turn, when it is one. */
export function openQuestion(turns: InterviewTurn[]): InterviewTurn | null {
  const last = turns.at(-1);
  return last?.from === "unblocker" && last.kind === "question" ? last : null;
}

/** The server's own words for a refusal, when it sent any. */
async function reasonIn(res: Response): Promise<string | undefined> {
  try {
    return ((await res.json()) as { error?: string }).error;
  } catch {
    return undefined;
  }
}

/**
 * `GET`: the conversation so far, seeded with the opening question when there is none. A question that is answered
 * or gone answers 409 with why, which is what the panel then says.
 */
export async function fetchInterview(plan: string, number: number): Promise<InterviewTurn[]> {
  const path = interviewPath(plan, number);
  const res = await fetch(path, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw new ApiError((res.status === 409 ? await reasonIn(res) : undefined) ?? `GET ${path} answered ${res.status}`, res.status);
  const body = (await res.json()) as { turns?: InterviewTurn[] };
  return Array.isArray(body.turns) ? body.turns : [];
}

/** `POST`: the person's turn as stored (202). The unblocker's reply arrives on the stream. */
export async function sendInterview(plan: string, number: number, text: string): Promise<InterviewTurn> {
  const path = interviewPath(plan, number);
  const res = await postJson(path, { id: ulid(), text });
  if (res.status === 202) return ((await res.json()) as { turn: InterviewTurn }).turn;
  const reason = res.status === 422 || res.status === 409 ? await reasonIn(res) : undefined;
  throw new ApiError(reason ?? `POST ${path} answered ${res.status}`, res.status);
}

/** Confirms the decision turn: the server writes its answer to blocked.md as the answer box would, then closes. */
export const confirmCommand = (plan: string, number: number, turnId: string): Omit<Command, "id"> =>
  ({ kind: "confirm_interview", plan, agent: null, payload: { question: String(number), turn: turnId } });

/** Sends the confirm straight to the gate, for callers with no command channel of their own. */
export async function confirmInterview(plan: string, number: number, turnId: string): Promise<Reply> {
  return postCommand(mintCommand(confirmCommand(plan, number, turnId)));
}
