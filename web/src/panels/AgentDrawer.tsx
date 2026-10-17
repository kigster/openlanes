// One agent up close, in place of the rail: its model (switched now), what it has cost, how full its context is, its
// question when it is stuck, its transcript behind a Show log toggle, and the composer with Send message and the Action
// menu beside it. The log starts closed every time the drawer opens, for a stuck agent too: the question is what the
// person must act on, and a full transcript under it pushed the composer off the bottom of the panel.
import { useEffect, useId, useRef, useState, type FormEvent, type KeyboardEvent } from "react";
import type { Car, ModelChoice, Plan, Question, Reply } from "../api/types";
import { AgentActionMenu, type AgentAction } from "./AgentActionMenu";
import { AnswerBox, Choices } from "./AskCard";
import { useAsk } from "./asks";
import { refusal, useCommand, type Outcome } from "./command";
import { Feedback } from "./feedback";
import { LastKnownTable } from "./LastKnownTable";
import { useQuestion } from "./question";
import { renderMarkdown } from "./markdown";
import { ModelSelect } from "./ModelSelect";
import { pend, unconfirmed, type Pending } from "./transcript";
import { ariaSendKeys, clock, fmt, isSendKey, modelName, sendKeys, type SendCommand } from "./support";

export interface AgentDrawerProps {
  plan: Plan;
  car: Car;
  models: ModelChoice[];
  /** Fraction of the context at which every agent autocompacts (W28). */
  autocompact: number;
  onCommand: SendCommand;
  onClose: () => void;
}

const SAID: Record<Exclude<AgentAction, "compact">, string> = {
  hold: "Asked to hold for now.",
  wrap_up: "Asked to wrap up.",
  stop: "Asked to stop.",
};
const compactSaid = (reply: Reply) => (reply.status === "done" ? "Compacted its context." : "Asked to compact its context; it runs /compact at its next step.");

function QuestionBlock({ plan, question, onCommand, onAnswered }: {
  plan: Plan; question: Question; onCommand: SendCommand; onAnswered: (text: string) => void;
}) {
  const q = useQuestion(plan, question, onCommand, onAnswered);
  return (
    <div className="d-block">
      <p><strong>Blocked on your answer.</strong></p>
      <div className="ask-text" dangerouslySetInnerHTML={{ __html: renderMarkdown(question.body) }} />
      {q.options && (
        <Choices options={q.options} onChoose={q.choose} onWords={() => q.update({ inWords: true })} inWords={q.inWords} disabled={q.command.pending} />
      )}
      {(!q.options || q.inWords) && (
        <>
          <AnswerBox id={`d-${question.id}`} value={q.state.draft} onChange={q.setDraft} onSend={q.answer} invalid={q.invalid} />
          <div className="ask-actions">
            <button type="button" className="btn btn-primary" aria-keyshortcuts={ariaSendKeys()} disabled={q.command.pending} onClick={q.answer}>Send answer</button>
          </div>
        </>
      )}
      <Feedback outcome={q.command.outcome?.tone === "refused" ? q.command.outcome : null} announced={q.command.announced} />
    </div>
  );
}

/**
 * The disclosure for the transcript; the count says there is something behind it before anyone opens it.
 * The count is the button's description, not part of its name: a name that changes with every new line is
 * re-announced to a screen reader each time. It is aria-hidden rather than left out of an aria-label, because an
 * aria-label missing visible text fails label-in-name; a description still reads a hidden element it points at.
 */
function LogToggle({ count, open, controls, onToggle }: { count: number; open: boolean; controls: string; onToggle: () => void }) {
  const countId = useId();
  return (
    <button type="button" className="btn btn-quiet log-toggle" aria-describedby={countId} aria-expanded={open} aria-controls={controls} onClick={onToggle}>
      <span className="log-caret" aria-hidden="true">{open ? "▾" : "▸"}</span>
      {open ? "Hide log" : "Show log"}
      <span id={countId} className="log-count" aria-hidden="true">{count === 1 ? "1 line" : `${count} lines`}</span>
    </button>
  );
}

export function AgentDrawer({ plan, car, models, autocompact, onCommand, onClose }: AgentDrawerProps) {
  const ids = { title: useId(), model: useId(), message: useId(), log: useId() };
  const command = useCommand(onCommand);
  const [mine, setMine] = useState<{ key: string; lines: Pending[] }>({ key: car.key, lines: [] });
  const history = useRef(car.history);
  useEffect(() => { history.current = car.history; }, [car.history]);
  const [text, setText] = useState("");
  const [refused, setRefused] = useState<Outcome | null>(null);
  // Keyed by car, so switching to another agent closes the log again rather than carrying the last one's choice over.
  const [log, setLog] = useState({ key: car.key, open: false });
  const logOpen = log.key === car.key && log.open;
  const close = useRef<HTMLButtonElement>(null);
  const field = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { close.current?.focus(); }, [car.key]);

  // Lines the person added this visit, newest first, until the snapshot's history carries them.
  const lines = unconfirmed(mine.key === car.key ? mine.lines : [], car.history).map((p) => p.text);
  // Forget the ones the history now holds, so a later trim of the history cannot bring them back.
  useEffect(() => {
    setMine((was) => {
      const kept = unconfirmed(was.lines, car.history);
      return kept.length === was.lines.length ? was : { ...was, lines: kept };
    });
  }, [car.history]);
  const push = (line: string) =>
    setMine((was) => ({ key: car.key, lines: pend(was.key === car.key ? was.lines : [], history.current, line) }));
  const say = (line: string) => push(`you: ${line}`);
  const heard = (said: string, wasRefused: boolean) => {
    if (wasRefused) setRefused({ tone: "refused", text: said });
    else { setRefused(null); say(said); }
  };

  const question = plan.questions.find((q) => q.agent === car.agent);
  const [askState] = useAsk(question?.id ?? "");
  const stuck = car.state === "stuck" && question && !askState.settled;

  const used = car.context !== null && car.context_limit ? car.context / car.context_limit : null;

  const act = async (kind: AgentAction) => {
    const reply = await command.send({ kind, plan: plan.ordinal, agent: car.agent, payload: {} }, kind === "compact" ? compactSaid : SAID[kind]);
    if (!reply) return;
    heard(reply.status === "refused" ? refusal(reply) : kind === "compact" ? compactSaid(reply) : SAID[kind], reply.status === "refused");
  };
  const send = async (e?: FormEvent) => {
    e?.preventDefault();
    const body = text.trim();
    if (!body) { field.current?.focus(); return; }
    const reply = await command.send({ kind: "message", plan: plan.ordinal, agent: car.agent, payload: { text: body } }, `Message sent to ${car.agent}.`);
    if (!reply) return;
    if (reply.status === "refused") { heard(refusal(reply), true); return; }
    heard(body, false);
    setText("");
  };
  const onKeyDown = (e: KeyboardEvent) => {
    if (e.key !== "Escape") return;
    // Esc inside the Action menu or the model list closes that, not the drawer.
    if ((e.target as HTMLElement).closest('[role="menu"], [role="listbox"]')) return;
    onClose();
  };

  return (
    <aside className="drawer" aria-labelledby={ids.title} onKeyDown={onKeyDown}>
      <div className="drawer-head">
        <div>
          <h2 id={ids.title}>{car.agent}</h2>
          <p className="drawer-meta">{plan.ordinal} {plan.title}. Model {modelName(models, car.model)}.</p>
        </div>
        <button type="button" className="btn btn-quiet" ref={close} onClick={onClose}>Close</button>
      </div>
      <div className="d-model">
        <label id={ids.model}>Model</label>
        <ModelSelect plan={plan.ordinal} car={car} models={models} mode="now" onCommand={onCommand} labelledBy={ids.model} onOutcome={heard} />
        <p className="d-model-help">Switches this agent now, then runs /compact.</p>
      </div>
      <div className="drawer-stats">
        <div>Tokens in<strong>{fmt(car.up)}</strong></div>
        <div>Tokens out<strong>{fmt(car.down)}</strong></div>
        <div>Elapsed<strong>{clock(car.elapsed)}</strong></div>
      </div>
      <div className="d-context">
        {used === null ? (
          <p>Context <strong>not reported</strong> by this adapter.</p>
        ) : (
          <p>
            Context <strong>{Math.round(used * 100)}%</strong>{" "}
            <span>of {fmt(car.context_limit ?? 0)}, {fmt(car.context ?? 0)} used. Autocompacts at {Math.round(autocompact * 100)}%.</span>
          </p>
        )}
        <div className="d-ctx-bar" aria-hidden="true">
          <i style={{ width: `${Math.min(1, used ?? 0) * 100}%` }} />
          <b title="Autocompacts here" style={{ left: `${autocompact * 100}%` }} />
        </div>
      </div>
      <LastKnownTable entries={plan.last_known} />
      {stuck && <QuestionBlock plan={plan} question={question} onCommand={onCommand} onAnswered={(t) => push(`You answered: ${t}`)} />}
      <LogToggle count={lines.length + car.history.length} open={logOpen} controls={ids.log} onToggle={() => setLog({ key: car.key, open: !logOpen })} />
      {/* Hidden, not unmounted, so aria-controls always names an element; aria-live goes with it, since a closed log
          announcing every new line would talk about a region the person chose not to look at. */}
      <ol id={ids.log} className="transcript" hidden={!logOpen} aria-live={logOpen ? "polite" : "off"} aria-label={`Transcript of ${car.agent}`}>
        {[...lines, ...car.history].map((line, i) => <li key={i}>{line}</li>)}
      </ol>
      <form className="composer" onSubmit={send}>
        <label htmlFor={ids.message}>Message {car.agent}</label>
        <textarea
          id={ids.message} ref={field} value={text} onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => { if (isSendKey(e)) { e.preventDefault(); void send(); } }}
          placeholder={`It reads this at its next step. ${sendKeys()} sends it.`}
        />
        <div className="composer-actions">
          <button type="submit" className="btn btn-primary" aria-keyshortcuts={ariaSendKeys()} disabled={command.pending}>Send message</button>
          <AgentActionMenu contextUsed={used} onAction={act} disabled={command.pending} />
        </div>
        <Feedback outcome={refused} announced={command.announced} />
      </form>
    </aside>
  );
}
