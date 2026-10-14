import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { Board, CopilotLog, Snapshot, WireBoard } from "./types";
import { fetchBoard, isFixtureMode, loadFixtureBoard } from "./client";
import { openStream, type ConnectionState } from "./events";
import { BOARD_KEY, COPILOT_KEY } from "./queryClient";
import { EMPTY_LOG, withTurn } from "./copilot";
import { replies } from "./replies";

export type { ConnectionState } from "./events";
export type { WireBoard } from "./types";

const newer = (old: Snapshot | undefined, next: Snapshot): Snapshot => (old && old.seq >= next.seq ? old : next);

/**
 * Reconciles two boards node by node: no node's snapshot is ever replaced by one with a lower `seq`. A GET that left
 * before a streamed snapshot and lands after it would otherwise roll the board back. Nodes absent from `next` have
 * left (their snapshot key expired), so they go.
 */
export function reconcile(old: WireBoard | undefined, next: WireBoard): WireBoard {
  if (!old) return next;
  const me = old.me && next.me && old.me.node.id === next.me.node.id ? newer(old.me, next.me) : next.me;
  const was = new Map(old.others.map(s => [s.node.id, s]));
  const others = next.others.map(s => newer(was.get(s.node.id), s));
  if (me === old.me && others.length === old.others.length && others.every((s, i) => s === old.others[i])) return old;
  return { me, others };
}

export interface BoardState {
  board: Board | undefined;
  /** The first GET /api/board has not answered yet. */
  isLoading: boolean;
  /** The server answered, but this machine's engine has not published a snapshot yet: `board` stays undefined. */
  waiting: boolean;
  error: Error | null;
  connection: ConnectionState;
  /** True under `?fixture`: the board is the sample file and nothing is live. */
  fixture: boolean;
}

/**
 * The page's whole state. TanStack Query holds the Board, first from `GET /api/board`, then from every `event: board`
 * on the stream; replies on the stream go to the reply bus, where useSendCommand waits for them.
 *
 * Call it once, at the top of the page: each call opens its own stream.
 */
export function useBoard(): BoardState {
  const fixture = isFixtureMode();
  const client = useQueryClient();
  const [connection, setConnection] = useState<ConnectionState>(fixture ? "live" : "reconnecting");
  // Counts stream events applied. A GET that sees it move while in flight left before the stream's news, and seq
  // cannot catch every such answer: `{me: null}` (the run finished) has no seq to lose to the snapshot it replaced.
  const streamed = useRef(0);
  const query = useQuery<WireBoard>({
    queryKey: BOARD_KEY,
    queryFn: fixture
      ? () => Promise.resolve(loadFixtureBoard())
      : async () => {
          const before = streamed.current;
          const board = await fetchBoard();
          return streamed.current === before ? board : (client.getQueryData<WireBoard>(BOARD_KEY) ?? board);
        },
    // A fetched board is reconciled with what the stream already delivered, never laid over it.
    structuralSharing: (old: unknown, next: unknown) => reconcile(old as WireBoard | undefined, next as WireBoard),
  });

  useEffect(() => {
    if (fixture) return;
    return openStream({
      onBoard: board => {
        // Drop any GET still in flight before applying the event, so its older answer never lands on top of it.
        // Cancelling reverts synchronously to the state before that GET, which the event then replaces.
        void client.cancelQueries({ queryKey: BOARD_KEY });
        streamed.current += 1;
        client.setQueryData<WireBoard>(BOARD_KEY, old => reconcile(old, board));
      },
      onReply: reply => replies.deliver(reply),
      // A turn that arrives before the conversation's GET has answered starts the log: that GET may have read the
      // stream already, and then this event is the turn's only copy. The GET's answer is merged in when it lands.
      onCopilot: turn => client.setQueryData<CopilotLog>(COPILOT_KEY, old => withTurn(old ?? EMPTY_LOG, turn)),
      onState: setConnection,
      // Read the conversation only once the stream has said where it starts; a read begun earlier could miss a turn
      // written before the stream opened, which the stream would then never send either. A read still in flight began
      // before the boundary, so cancel it first: refetchQueries alone reuses it while the log has no data yet.
      onCopilotCursor: () => {
        void client.cancelQueries({ queryKey: COPILOT_KEY });
        void client.refetchQueries({ queryKey: COPILOT_KEY });
      },
      onReconnect: () => void client.refetchQueries({ queryKey: BOARD_KEY }),
    });
  }, [client, fixture]);

  const data = query.data;
  // The page below works on a Board whose `me` is there; until it is, there is no board to show.
  const board = useMemo<Board | undefined>(() => (data?.me ? { me: data.me, others: data.others } : undefined), [data]);
  return { board, isLoading: query.isPending, waiting: !!data && !data.me, error: query.error, connection, fixture };
}
