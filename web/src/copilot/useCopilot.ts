import { useCallback, useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ulid } from "ulid";
import { fetchCopilot, isFixtureMode, postCopilot } from "../api/client";
import { EMPTY_LOG, answers, asLog, mergeLogs, withTurn } from "../api/copilot";
import { COPILOT_KEY } from "../api/queryClient";
import type { CopilotLog, CopilotTurn } from "../api/types";

/**
 * How long the panel shows the copilot as reading before it stops waiting for an answer: a little past the 180 s
 * c3po-operator's definition allows one answer, after which the server writes why it gave up.
 */
export const ANSWER_TIMEOUT_MS = 200_000;

/** What `?fixture` answers, since nothing is connected to answer for real. */
export const FIXTURE_REPLY = "This page is showing fixture data, so nothing is connected to answer you.";

export interface CopilotState {
  log: CopilotLog;
  /** Sends a message. Rejects with the reason when it was not stored. */
  send(text: string): Promise<void>;
  /** A message was stored and its answer has not arrived yet. */
  waiting: boolean;
  /** The first load has answered: what it brought was said before this visit. */
  ready: boolean;
}

/**
 * The conversation with the copilot (contract.md, "Copilot"): `GET /api/copilot` once, then every `event: copilot`
 * that useBoard's stream adds to the same query. Sending posts the message and shows it at once; the stream brings
 * the stored copy, which the merge recognises by its id.
 */
export function useCopilot(): CopilotState {
  const fixture = isFixtureMode();
  const client = useQueryClient();
  const query = useQuery<CopilotLog>({
    queryKey: COPILOT_KEY,
    queryFn: fixture ? () => Promise.resolve(EMPTY_LOG) : async () => asLog(await fetchCopilot()),
    structuralSharing: (held: unknown, fetched: unknown) => mergeLogs(held as CopilotLog | undefined, fetched as CopilotLog),
  });
  const log = query.data ?? EMPTY_LOG;
  const [pending, setPending] = useState<string | null>(null);

  const add = useCallback(
    (turn: CopilotTurn) => client.setQueryData<CopilotLog>(COPILOT_KEY, old => withTurn(old ?? EMPTY_LOG, turn)),
    [client],
  );

  const send = useCallback(
    async (text: string) => {
      const id = ulid();
      const at = new Date().toISOString();
      if (fixture) {
        add({ id, from: "you", kind: "text", text, at, usage: null });
        add({ id: `${id}.1`, from: "copilot", kind: "text", text: FIXTURE_REPLY, at, usage: null });
        return;
      }
      add(await postCopilot({ id, text }));
      setPending(id);
    },
    [add, fixture],
  );

  const answered = pending !== null && log.turns.some(t => answers(t, pending));
  useEffect(() => {
    if (pending === null) return;
    if (answered) {
      setPending(null);
      return;
    }
    const timer = setTimeout(() => setPending(null), ANSWER_TIMEOUT_MS);
    return () => clearTimeout(timer);
  }, [pending, answered]);

  return { log, send, waiting: pending !== null && !answered, ready: query.isSuccess };
}
