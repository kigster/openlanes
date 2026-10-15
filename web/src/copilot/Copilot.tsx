// The copilot (W17): a conversation with c3po-operator about the run, in a floating panel docked bottom right. The API
// server runs the agent and checks every card it offers before storing it (contract.md, "Copilot"), so a card drawn
// here is one the command gate takes; nothing is sent until the person presses its button.
import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from "react";
import type { CopilotReply, CopilotTurn, ModelChoice } from "../api/types";
import { FloatingPanel } from "../floating";
import { COPILOT_COLORS } from "./colors";
import { useAskStore } from "../panels/asks";
import { useCommand } from "../panels/command";
import { ariaSendKeys, fmt, isSendKey, modelName, sendKeys, type SendCommand } from "../panels/support";
import { useCopilot, useCopilotOpenRequests } from "./useCopilot";
import "./copilot.css";

const OPEN_KEY = "openlanes-copilot-open";

function readOpen(): boolean {
  try {
    return localStorage.getItem(OPEN_KEY) === "1";
  } catch {
    return false; // a private window: start minimised
  }
}

function writeOpen(open: boolean): void {
  try {
    localStorage.setItem(OPEN_KEY, open ? "1" : "");
  } catch {
    // a private window: the choice lasts for this visit
  }
}

/** A red card: the copilot proposes a command that cannot be undone, and only the person's press sends it. */
export function ConfirmCard({ turn, onCommand }: { turn: Extract<CopilotReply, { kind: "confirm" }>; onCommand: SendCommand }) {
  const { send, outcome, pending } = useCommand(onCommand);
  const [dismissed, setDismissed] = useState(false);
  if (dismissed) return <p className="cp-card-note">Left as it is.</p>;
  if (outcome) return <p className={`cp-card-note${outcome.tone === "refused" ? " is-refused" : ""}`}>{outcome.text}</p>;
  return (
    <div className="cp-card is-confirm">
      <div className="cp-card-actions">
        <button type="button" className="btn btn-alarm" disabled={pending} onClick={() => void send(turn.command, turn.done)}>
          {turn.confirm}
        </button>
        <button type="button" className="btn btn-quiet" disabled={pending} onClick={() => setDismissed(true)}>
          Not now
        </button>
      </div>
    </div>
  );
}

/** A quiet card: a drafted answer, put into the question's answer box and never sent from here. */
export function DraftCard({ turn }: { turn: Extract<CopilotReply, { kind: "draft" }> }) {
  const asks = useAskStore();
  const [placed, setPlaced] = useState(false);
  if (placed) return <p className="cp-card-note">It is in the answer box under Needs you. Nothing is sent until you send it.</p>;
  return (
    <div className="cp-card is-draft">
      <p className="cp-draft">{turn.draft}</p>
      <div className="cp-card-actions">
        <button
          type="button"
          className="btn btn-primary"
          onClick={() => {
            asks.update(turn.question, { draft: turn.draft, inWords: true });
            setPlaced(true);
          }}
        >
          Put it in the answer box
        </button>
      </div>
    </div>
  );
}

function Turn({ turn, onCommand }: { turn: CopilotTurn; onCommand: SendCommand }) {
  const you = turn.from === "you";
  return (
    <div className={`cp-turn${you ? " is-you" : ""}`} data-turn={turn.id}>
      <p className="cp-who">{you ? "You" : "c3po-operator"}</p>
      <div className="cp-said">
        <p>{turn.text}</p>
        {turn.from === "copilot" && turn.kind === "confirm" && <ConfirmCard turn={turn} onCommand={onCommand} />}
        {turn.from === "copilot" && turn.kind === "draft" && <DraftCard turn={turn} />}
      </div>
    </div>
  );
}

export interface CopilotProps {
  onCommand: SendCommand;
  /** The adapter's models, to name the copilot's in its header. */
  models?: ModelChoice[];
}

export function Copilot({ onCommand, models = [] }: CopilotProps) {
  const { log, send, waiting, ready } = useCopilot();
  const [open, setOpenState] = useState(readOpen);
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const chat = useRef<HTMLDivElement>(null);

  // The dot on the tab: a copilot turn newer than the last one seen with the panel open. Whatever the first load
  // brings was said before this visit, so it is not news.
  const latest = log.turns.filter(t => t.from === "copilot").at(-1)?.id ?? null;
  const [seen, setSeen] = useState<string | null | undefined>(undefined);
  useEffect(() => {
    if (open || (seen === undefined && ready)) setSeen(latest);
  }, [open, latest, seen, ready]);
  const unread = !open && seen !== undefined && latest !== seen;

  useLayoutEffect(() => {
    const el = chat.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [log.turns.length, waiting, open]);

  const setOpen = (next: boolean) => {
    setOpenState(next);
    writeOpen(next);
  };

  // Another panel asked to talk a plan over: open, and start the message unless the person has one going already.
  useCopilotOpenRequests(({ text: start }) => {
    setOpen(true);
    setText(was => (was.trim() ? was : start));
    input.current?.focus();
  });

  const submit = async (e?: FormEvent) => {
    e?.preventDefault();
    const message = text.trim();
    if (!message || sending) {
      input.current?.focus();
      return;
    }
    setSending(true);
    setError(null);
    try {
      await send(message);
      setText("");
    } catch (failure) {
      setError(`Not sent: ${failure instanceof Error ? failure.message : String(failure)}`);
    } finally {
      setSending(false);
    }
  };

  const usage = log.usage;
  const subtitle = (
    <>
      Copilot for this run. {usage.model ? modelName(models, usage.model) : "Not running"}, ↑ {fmt(usage.up)} ↓ {fmt(usage.down)}
    </>
  );

  return (
    <FloatingPanel
      id="copilot"
      className="copilot"
      dock="right"
      title="c3po-operator"
      subtitle={subtitle}
      tabLabel="Copilot"
      moves="the copilot"
      open={open}
      onOpenChange={setOpen}
      unread={unread}
      colors={COPILOT_COLORS}
      live
      bodyLabel="Conversation with c3po-operator"
      bodyRef={chat}
      initialFocus={input}
      footer={
        <form className="cp-composer" onSubmit={e => void submit(e)}>
          <label className="sr-only" htmlFor="copilot-input">
            Message c3po-operator
          </label>
          <textarea
            id="copilot-input"
            ref={input}
            value={text}
            placeholder={`Ask about the run. ${sendKeys()} sends it.`}
            aria-keyshortcuts={ariaSendKeys()}
            onChange={e => setText(e.target.value)}
            onKeyDown={e => {
              if (isSendKey(e)) {
                e.preventDefault();
                void submit();
              }
            }}
          />
          {error && (
            <p className="cp-error" role="alert">
              {error}
            </p>
          )}
          <div className="cp-actions">
            <button type="submit" className="btn btn-primary" disabled={sending}>
              Send
            </button>
          </div>
        </form>
      }
    >
      {log.turns.length === 0 && (
        <p className="cp-intro">
          Ask c3po-operator about the run: why a plan is stuck, what it costs, or for a draft answer to an agent. It asks
          before anything that cannot be undone.
        </p>
      )}
      {log.turns.map(turn => (
        <Turn key={turn.id} turn={turn} onCommand={onCommand} />
      ))}
      {waiting && (
        <div className="cp-turn is-thinking">
          <p className="cp-who">c3po-operator</p>
          <p className="cp-said">Reading the board…</p>
        </div>
      )}
    </FloatingPanel>
  );
}
