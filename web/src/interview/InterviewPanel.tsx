// The unblocker's interview about one question, in a floating panel built like the copilot's. It asks one question at
// a time, each with a recommended answer; the person answers with a button or in words, and the last turn is a
// decision they confirm. Nothing is written until then. Leaving the panel deletes nothing: the question card keeps its
// own buttons and text box.
import { useLayoutEffect, useRef, useState, type FormEvent } from "react";
import type { InterviewTurn, Question } from "../api/types";
import { confirmCommand, openQuestion, pendingDecision } from "../api/interview";
import { FloatingPanel } from "../floating";
import { COPILOT_COLORS } from "../copilot/colors";
import { ariaSendKeys, isSendKey, sendKeys, type SendCommand } from "../panels/support";
import { refusal } from "../panels/command";
import { useInterview } from "./useInterview";
import "./interview.css";

export interface InterviewPanelProps {
  plan: string;
  question: Question;
  onCommand: SendCommand;
  /** The panel was closed, or the interview ended with a confirmed decision. */
  onClose: () => void;
}

function Turn({ turn }: { turn: InterviewTurn }) {
  const you = turn.from === "you";
  return (
    <div className={`iv-turn${you ? " is-you" : ""}`} data-turn={turn.id}>
      <p className="iv-who">{you ? "You" : "unblocker"}</p>
      <div className="iv-said"><p>{turn.text}</p></div>
    </div>
  );
}

export function InterviewPanel({ plan, question, onCommand, onClose }: InterviewPanelProps) {
  const { turns, send, waiting, ready } = useInterview(plan, question.number);
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const body = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const el = body.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [turns.length, waiting]);

  const ask = openQuestion(turns);
  const decision = pendingDecision(turns);

  const say = async (message: string) => {
    const value = message.trim();
    if (!value || busy) { input.current?.focus(); return; }
    setBusy(true);
    setError(null);
    try {
      await send(value);
      setText("");
    } catch (failure) {
      setError(`Not sent: ${failure instanceof Error ? failure.message : String(failure)}`);
    } finally {
      setBusy(false);
    }
  };
  const submit = (e?: FormEvent) => { e?.preventDefault(); void say(text); };

  const yes = async (turn: InterviewTurn) => {
    setBusy(true);
    setError(null);
    try {
      const reply = await onCommand(confirmCommand(plan, question.number, turn.id));
      if (reply.status === "refused") setError(refusal(reply));
      else onClose();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
    } finally {
      setBusy(false);
    }
  };

  return (
    <FloatingPanel
      id={`interview-${plan}-${question.number}`}
      className="copilot interview"
      dock="left"
      title="unblocker"
      subtitle={<>Talking through {plan}: {question.heading}</>}
      tabLabel="Interview"
      moves="the interview"
      open
      onOpenChange={open => { if (!open) onClose(); }}
      colors={COPILOT_COLORS}
      live
      bodyLabel="Interview with the unblocker"
      bodyRef={body}
      initialFocus={input}
      footer={
        <form className="cp-composer iv-composer" onSubmit={submit}>
          <label className="sr-only" htmlFor="interview-input">Your reply</label>
          <textarea
            id="interview-input" ref={input} value={text}
            placeholder={`Answer in your own words. ${sendKeys()} sends it.`}
            aria-keyshortcuts={ariaSendKeys()}
            onChange={e => setText(e.target.value)}
            onKeyDown={e => { if (isSendKey(e)) { e.preventDefault(); submit(); } }}
          />
          {error && <p className="iv-note is-refused" role="alert">{error}</p>}
          <div className="cp-card-actions">
            <button type="submit" className="btn btn-primary" disabled={busy}>Send</button>
            <button type="button" className="btn btn-quiet" onClick={onClose}>Answer on the card instead</button>
          </div>
        </form>
      }
    >
      {!ready && <p className="iv-note">Opening the conversation…</p>}
      {turns.map(turn => <Turn key={turn.id} turn={turn} />)}
      {ask && (
        <div className="iv-options" role="group" aria-label="Choose an answer">
          {ask.options?.map(option => (
            <button
              key={option.label} type="button" disabled={busy}
              className={`btn btn-choice${option.recommended ? " is-recommended btn-recommended" : ""}`}
              onClick={() => void say(option.label)}
            >
              <span className="choice-label">{option.label}</span>
              {option.recommended && <span className="choice-tag">Recommended</span>}
            </button>
          ))}
        </div>
      )}
      {decision && (
        <div className="iv-decision">
          <p className="iv-note">This is what will be written as the answer. Nothing is written until you confirm.</p>
          <p>{decision.answer}</p>
          <div className="cp-card-actions">
            <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void yes(decision)}>Confirm</button>
          </div>
        </div>
      )}
      {waiting && <p className="iv-note" aria-live="polite">The unblocker is thinking…</p>}
    </FloatingPanel>
  );
}
