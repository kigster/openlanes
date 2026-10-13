// The page's only door to the API server (contract.md, "HTTP"). Everything that crosses the network goes through
// here, so the tests mock fetch once and every caller is covered.
import { ulid } from "ulid";
import type { Board, Command, Node, Reply, WireBoard } from "./types";
import fixtureBoard from "./fixtures/board.json";

export interface Session {
  csrf: string;
  node: Node;
  repo: string;
}

/** A command as a caller writes it: the id is minted here, so a retry can never mint a second one by accident. */
export type CommandInput = Omit<Command, "id">;

export class ApiError extends Error {
  readonly status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

/**
 * `?fixture` on the page's URL serves web/src/api/fixtures/board.json and never touches the network, so the board can
 * be worked on without `openlanes web --demo` running.
 */
export function isFixtureMode(search: string = window.location.search): boolean {
  return new URLSearchParams(search).has("fixture");
}

export function loadFixtureBoard(): Board {
  // A deep copy, so a test or a dev session that mutates what it got never changes the next caller's board.
  return structuredClone(fixtureBoard as Board);
}

async function getJson<T>(path: string): Promise<T> {
  const res = await fetch(path, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw new ApiError(`GET ${path} answered ${res.status}`, res.status);
  return (await res.json()) as T;
}

export const fetchBoard = (): Promise<WireBoard> => getJson<WireBoard>("/api/board");

let session: Promise<Session> | null = null;

/** The session, fetched once per page; a failed fetch is forgotten so the next caller tries again. */
export function getSession(): Promise<Session> {
  session ??= getJson<Session>("/api/session").catch((error: unknown) => {
    session = null;
    throw error;
  });
  return session;
}

/** Forgets the cached session. The tests use it; so does postCommand when the server stops accepting the token. */
export function resetSession(): void {
  session = null;
}

export function mintCommand(input: CommandInput): Command {
  return { id: ulid(), ...input };
}

async function send(command: Command, csrf: string): Promise<Response> {
  return fetch("/api/commands", {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf },
    body: JSON.stringify(command),
  });
}

/**
 * Sends one command. Resolves with the server's first reply: `accepted` once it is queued (202) or `refused` when it
 * is invalid (422). A 403 means the token went stale (the server restarted), so it fetches a new one and sends the
 * same command, same id, once more; the id is the idempotency key, so the engine cannot apply it twice.
 */
export async function postCommand(command: Command): Promise<Reply> {
  let res = await send(command, (await getSession()).csrf);
  if (res.status === 403) {
    resetSession();
    // The command was refused, so failing to get a fresh token is as definite as the 403 itself.
    const fresh = await getSession().catch(() => {
      throw new ApiError("POST /api/commands answered 403 and no new session could be fetched", 403);
    });
    res = await send(command, fresh.csrf);
  }
  if (res.status === 202 || res.status === 422) return (await res.json()) as Reply;
  throw new ApiError(`POST /api/commands answered ${res.status}`, res.status);
}
