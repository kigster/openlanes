// The chat's panel (D11): the shared FloatingPanel docked bottom left in orange, minimising to a tab on the left edge
// and returning to its corner when restored. Its header lists who is in the chat; its footer is the composer, where
// Cmd-Enter (Ctrl-Enter elsewhere) sends.
import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from "react";
import { FloatingPanel } from "../floating";
import { ariaSendKeys, isSendKey, sendKeys } from "../panels/support";
import { CHAT_COLORS } from "./colors";
import { linkify } from "./linkify";
import { LIMIT, type Chat } from "./useChat";

export function ChatPanel({ chat }: { chat: Chat }) {
  const room = chat.room;
  // A page that loads into a chat starts minimised; starting or joining one opens it.
  const [open, setOpen] = useState(false);
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [seen, setSeen] = useState(chat.heard);
  const input = useRef<HTMLTextAreaElement>(null);
  const body = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (chat.entered > 0) setOpen(true);
  }, [chat.entered]);

  useEffect(() => {
    if (open) setSeen(chat.heard);
  }, [open, chat.heard]);

  // Clicking, focusing or pressing any key anywhere in the panel counts as being there (D7), the header and its
  // buttons included: an arrow key moves no text, and is still somebody at the keyboard.
  const { touch } = chat;
  const present = room !== null;
  useEffect(() => {
    const panel = document.getElementById("chat");
    if (!panel || !present) return;
    panel.addEventListener("pointerdown", touch);
    panel.addEventListener("focusin", touch);
    panel.addEventListener("keydown", touch);
    return () => {
      panel.removeEventListener("pointerdown", touch);
      panel.removeEventListener("focusin", touch);
      panel.removeEventListener("keydown", touch);
    };
  }, [touch, present]);

  useLayoutEffect(() => {
    const el = body.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [chat.entries.length, open]);

  if (!room) return null;
  const names = room.participants.map(p => (p.idle ? `${p.name} (idle)` : p.name)).join(", ");
  const over = text.length > LIMIT;

  const submit = async (e?: FormEvent) => {
    e?.preventDefault();
    chat.touch();
    const message = text.trim();
    if (!message || sending || over) {
      input.current?.focus();
      return;
    }
    setSending(true);
    setError(null);
    try {
      await chat.say(message);
      setText("");
    } catch (failure) {
      setError(`Not sent: ${failure instanceof Error ? failure.message : String(failure)}`);
    } finally {
      setSending(false);
    }
  };

  return (
    <FloatingPanel
      id="chat"
      className="chat"
      dock="left"
      restore="dock"
      title={names || "Chat"}
      subtitle="Chat between machines. Nothing said is kept."
      tabLabel="Chat"
      moves="the chat"
      open={open}
      onOpenChange={setOpen}
      unread={!open && chat.heard !== seen}
      colors={CHAT_COLORS}
      live
      bodyLabel="Chat between machines"
      bodyRef={body}
      initialFocus={input}
      footer={
        <form className="chat-composer" onSubmit={e => void submit(e)}>
          <label className="sr-only" htmlFor="chat-input">
            Message everyone in the chat
          </label>
          <textarea
            id="chat-input"
            ref={input}
            value={text}
            placeholder={`Say something. ${sendKeys()} sends it.`}
            aria-keyshortcuts={ariaSendKeys()}
            aria-invalid={over || undefined}
            aria-describedby="chat-count"
            onChange={e => {
              setText(e.target.value);
              chat.touch();
            }}
            onKeyDown={e => {
              if (isSendKey(e)) {
                e.preventDefault();
                void submit();
              }
            }}
          />
          {error && (
            <p className="chat-error" role="alert">
              {error}
            </p>
          )}
          <div className="chat-actions">
            <span id="chat-count" className={`chat-count${over ? " is-over" : ""}`}>
              {over ? `${text.length - LIMIT} characters over the ${LIMIT.toLocaleString("en")} limit` : `${text.length.toLocaleString("en")} / ${LIMIT.toLocaleString("en")}`}
            </span>
            <button type="submit" className="btn btn-primary" disabled={sending || over}>
              Send
            </button>
          </div>
        </form>
      }
    >
      <div className="chat-log">
        {chat.entries.map(entry =>
          entry.type === "notice" ? (
            <p key={entry.id} className="chat-notice">
              {entry.text}
            </p>
          ) : (
            <div key={entry.id} className={`chat-said${entry.mine ? " is-mine" : ""}`} data-said={entry.id}>
              <p className="chat-who">
                {entry.mine ? "You" : entry.who.name} <span className="chat-where">{entry.who.label}</span>
              </p>
              <p className="chat-text">{linkify(entry.text)}</p>
            </div>
          ),
        )}
      </div>
    </FloatingPanel>
  );
}
