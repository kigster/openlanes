// The chat's two centred dialogs: the Name dialog, asked on every start and every accepted invite (D8), and the
// invite modal every page on the invited machine shows until one answers (D9).
import { useEffect, useRef, useState, type FormEvent } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import type { ChatInvite } from "../api/types";
import { Frame } from "../panels/dialogs";
import type { NameRequest } from "./context";
import { lastName } from "./useChat";

/** Characters a name may carry; the server says the same. */
export const NAME_LIMIT = 60;

export interface NameDialogProps {
  request: NameRequest | null;
  /** This machine's user, the suggestion when this browser has never named itself. */
  user: string;
  /** Why the dialog can no longer do what it was opened for, when that happened while it was open. */
  gone?: string | null;
  onCancel(): void;
  onConfirm(name: string): Promise<void>;
}

export function NameDialog({ request, user, gone = null, onCancel, onConfirm }: NameDialogProps) {
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  // Joined: focus goes to the chat's composer, not back to the menu that opened this.
  const joined = useRef(false);

  // Prefilled every time it opens (D8), with the name last used here or the machine's user.
  useEffect(() => {
    if (!request) return;
    setName(lastName(user));
    setError(null);
  }, [request, user]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const typed = name.trim();
    if (!typed) {
      setError("A name is needed: it is how the others see you in the chat.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await onConfirm(typed);
      joined.current = true;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
    } finally {
      setBusy(false);
    }
  };

  const starting = request?.kind === "start";
  const title = starting ? `Chat with ${request.label}` : "Join the chat";
  const what = starting
    ? `Starts a chat and invites ${request.label}. Nothing said is kept.`
    : request
      ? `${request.invite.from.name} (${request.invite.from.label}) invited you. Nothing said is kept.`
      : "";

  return (
    <Dialog.Root open={request !== null} onOpenChange={open => !open && onCancel()}>
      <Frame
        className="confirm chat-name"
        title={title}
        description={<Dialog.Description asChild><p>{what}</p></Dialog.Description>}
        onOpenAutoFocus={e => {
          e.preventDefault();
          input.current?.select();
          input.current?.focus();
        }}
        onCloseAutoFocus={e => {
          if (!joined.current) return;
          joined.current = false;
          e.preventDefault();
          document.getElementById("chat-input")?.focus();
        }}
      >
        <form onSubmit={e => void submit(e)}>
          <div className="help-body">
            <label className="chat-label" htmlFor="chat-name">
              Name
            </label>
            <input
              id="chat-name"
              ref={input}
              className="chat-name-input"
              value={name}
              maxLength={NAME_LIMIT}
              autoComplete="nickname"
              onChange={e => setName(e.target.value)}
              aria-describedby={error || gone ? "chat-name-error" : undefined}
            />
            {(error || gone) && (
              <p id="chat-name-error" className="chat-error" role="alert">
                {gone ?? error}
              </p>
            )}
          </div>
          <div className="help-foot">
            <Dialog.Close className="btn btn-quiet" type="button">
              Cancel
            </Dialog.Close>
            <button type="submit" className="btn btn-primary" disabled={busy || !!gone}>
              {starting ? "Start" : "Join"}
            </button>
          </div>
        </form>
      </Frame>
    </Dialog.Root>
  );
}

export interface InviteDialogProps {
  invite: ChatInvite | null;
  /** This page is in a chat already: accepting leaves it (D4). */
  inChat: boolean;
  onDecline(invite: ChatInvite): void;
  onAccept(invite: ChatInvite): void;
}

export function InviteDialog({ invite, inChat, onDecline, onAccept }: InviteDialogProps) {
  // The last invite shown, so the dialog keeps its words while it closes.
  const shown = useRef<ChatInvite | null>(null);
  if (invite) shown.current = invite;
  const i = invite ?? shown.current;
  return (
    <Dialog.Root open={invite !== null} onOpenChange={open => !open && invite && onDecline(invite)}>
      {i && (
        <Frame
          className="confirm chat-invite"
          title="Invitation to chat"
          description={
            <Dialog.Description asChild>
              <p>
                <strong>{i.from.name}</strong> on {i.from.label} invites you to a chat.
                {inChat && " You are in a chat now: accepting leaves it."}
              </p>
            </Dialog.Description>
          }
        >
          <div className="help-foot">
            <button type="button" className="btn btn-quiet" onClick={() => onDecline(i)}>
              Decline
            </button>
            <button type="button" className="btn btn-primary" onClick={() => onAccept(i)}>
              Accept
            </button>
          </div>
        </Frame>
      )}
    </Dialog.Root>
  );
}
