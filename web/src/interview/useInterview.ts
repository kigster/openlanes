import { useCallback, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchInterview, interviewKey, mergeTurns, sendInterview, withTurn } from "../api/interview";
import { ApiError, isFixtureMode } from "../api/client";
import type { InterviewTurn } from "../api/types";

export interface InterviewState {
  turns: InterviewTurn[];
  /** The first load has answered. */
  ready: boolean;
  /** Why the conversation could not be read, when it could not and there is nothing to show in its place. */
  error: string | null;
  /** A message was sent and the unblocker's next turn has not arrived. */
  waiting: boolean;
  /** Sends a message. Rejects with the reason when it was not stored. */
  send(text: string): Promise<void>;
}

/**
 * One question's interview: `GET` once, then every `event: interview` that useBoard's stream adds to the same query,
 * so a reload or a second machine shows the same conversation. Sending shows the person's turn at once; the stream's
 * copy has the same id and is drawn once.
 */
export function useInterview(plan: string, number: number, enabled = true): InterviewState {
  const client = useQueryClient();
  const key = interviewKey(plan, number);
  const query = useQuery<InterviewTurn[]>({
    queryKey: key,
    enabled,
    queryFn: isFixtureMode() ? () => Promise.resolve([]) : () => fetchInterview(plan, number),
    // A refusal is the answer, not a fault to try again: a question that is closed stays closed, and the panel should
    // say so at once instead of "Opening…" through two more tries.
    retry: (failures, error) => failures < 2 && !(error instanceof ApiError && error.status < 500),
    structuralSharing: (held: unknown, fetched: unknown) => mergeTurns(held as InterviewTurn[] | undefined, fetched as InterviewTurn[]),
  });
  const turns = query.data ?? [];
  const [sentOn, setSentOn] = useState<number | null>(null);
  // Waiting ends when anything from the unblocker lands after the message that started it.
  const last = turns.at(-1);
  const waiting = sentOn !== null && (last === undefined || last.from === "you");

  const send = useCallback(
    async (text: string) => {
      const turn = await sendInterview(plan, number, text);
      client.setQueryData<InterviewTurn[]>(key, old => withTurn(old ?? [], turn));
      setSentOn(turns.length);
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [client, plan, number, turns.length],
  );
  // A failed refetch over turns already drawn says nothing: the turns stand, and the stream still adds to them.
  const error = query.isError && turns.length === 0 ? query.error.message : null;
  return { turns, ready: query.isSuccess, error, waiting, send };
}
