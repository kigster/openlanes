// One request as a card: a question an agent asked. Needs you shows it in the rail,
// the unblock widget across the board, and the drawer the question part of it; the logic is here once for all three.
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import type { Plan, Question, QuestionOption } from "../api/types";
import { Feedback } from "./feedback";
import { renderMarkdown } from "./markdown";
import { MarkdownEditor } from "./MarkdownEditor";
import { isWord, useQuestion, type Ask } from "./question";
import { ariaSendKeys, isSendKey, optionsOnly, sendKeys, type SendCommand } from "./support";

const FADE_MS = 500;
const capital = (word: string) => word.charAt(0).toUpperCase() + word.slice(1);

function HoldButton({ held, onClick, disabled }: { held: boolean; onClick: () => void; disabled: boolean }) {
  return (
    <button
      type="button" className="btn btn-quiet" aria-pressed={held} disabled={disabled} onClick={onClick}
      title={held ? "Let the agent's question go back to waiting normally" : "Keep this agent blocked until you answer; nothing else unblocks it"}
    >
      {held ? "Release hold" : "Hold blocked"}
    </button>
  );
}

/**
 * A question's options, one full-width button each, stacked (D3), the recommended one tagged and filled green; then "Type something
 * instead", always the last choice, which opens the text box under them. Once it is open the button goes, and the
 * box's own Send takes its place. A request for more time (E1) has nothing to say in words, so it has no such choice.
 */
export function Choices({ options, onChoose, onWords, inWords, disabled, words = true, children }: {
  options: QuestionOption[]; onChoose: (option: QuestionOption) => void; onWords: () => void; inWords: boolean;
  disabled: boolean; words?: boolean; children?: ReactNode;
}) {
  return (
    <>
      <div className="ask-choices" role="group" aria-label="Choose an answer">
        {options.map((option) => (
          <button
            key={option.letter} type="button" className={`btn btn-choice${option.recommended ? " is-recommended btn-recommended" : ""}`}
            disabled={disabled} onClick={() => onChoose(option)}
          >
            {!isWord(option) && <span className="choice-letter" aria-hidden="true">{option.letter})</span>}
            <span className="choice-label">{isWord(option) ? capital(option.label) : option.label}</span>
            {option.recommended && <span className="choice-tag">Recommended</span>}
          </button>
        ))}
        {words && !inWords && <button type="button" className="btn btn-choice btn-words" onClick={onWords}>Type something instead</button>}
      </div>
      {children && <div className="ask-actions">{children}</div>}
    </>
  );
}

/** A plain answer box: the rail's and the drawer's. ⌘ Enter sends. */
export function AnswerBox({ id, value, onChange, onSend, invalid, label = "Your answer" }: {
  id: string; value: string; onChange: (v: string) => void; onSend: () => void; invalid: boolean; label?: string;
}) {
  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (isSendKey(e)) { e.preventDefault(); onSend(); }
  };
  return (
    <>
      <label className="sr-only" htmlFor={id}>{label}</label>
      <textarea
        id={id} value={value} onChange={(e) => onChange(e.target.value)} onKeyDown={onKeyDown}
        aria-invalid={invalid || undefined}
        placeholder={invalid ? "Type an answer first" : `Your answer. ${sendKeys()} sends it.`}
      />
    </>
  );
}

function Who({ plan, agent, held }: { plan: Plan; agent: string | null; held?: boolean }) {
  return (
    <p className="ask-who">
      {plan.ordinal} — {agent ?? "agent"}
      {held && <> <span className="ask-held">held blocked</span></>}
    </p>
  );
}

/** Fades the card out over half a second after a hold, then reports it gone. */
function useLeaving(onLeft?: () => void) {
  const [leaving, setLeaving] = useState(false);
  const [gone, setGone] = useState(false);
  const left = useRef(onLeft);
  useEffect(() => { left.current = onLeft; }, [onLeft]);
  useEffect(() => {
    if (!leaving) return;
    const timer = setTimeout(() => { setGone(true); left.current?.(); }, FADE_MS);
    return () => clearTimeout(timer);
  }, [leaving]);
  return { leaving, gone, leave: () => setLeaving(true) };
}

function QuestionCard({ plan, question, variant, onCommand, onLeft }: {
  plan: Plan; question: Question; variant: "rail" | "widget"; onCommand: SendCommand; onLeft?: () => void;
}) {
  const q = useQuestion(plan, question, onCommand);
  const { leaving, gone, leave } = useLeaving(onLeft);
  const [heldNote, setHeldNote] = useState(false);
  const pending = q.command.pending;
  const hold = async () => {
    if (await q.toggleHold()) { setHeldNote(true); leave(); }
  };
  if (gone) return null;
  if (q.state.settled || heldNote) {
    const note = heldNote ? `Held blocked. ${plan.ordinal} stays red in the status bar; click it to answer.` : q.state.settled;
    return <div className={`ask is-done${leaving ? " is-leaving" : ""}`} data-ask={question.id}><p className="ask-done">{note}</p></div>;
  }
  const holdButton = <HoldButton held={q.isHeld} onClick={hold} disabled={pending} />;
  const body = <div className="ask-text" dangerouslySetInnerHTML={{ __html: renderMarkdown(question.body) }} />;
  // The text box: the whole answer for a question that offers nothing to choose, the last choice for one that does.
  const box = variant === "widget" ? (
    <div className="unblock-answer">
      <MarkdownEditor
        value={q.state.draft} onChange={q.setDraft} onSubmit={q.answer} label="Your answer" invalid={q.invalid}
        placeholder={q.invalid ? "Type an answer first" : `Your answer, in Markdown. ${sendKeys()} sends it.`}
        height="180px" resizable autoFocus={!question.held && !q.options}
      />
      <div className="unblock-buttons">
        <button type="button" className="btn btn-primary" aria-keyshortcuts={ariaSendKeys()} disabled={pending} onClick={q.answer}>Send answer</button>
        {holdButton}
      </div>
    </div>
  ) : (
    <>
      <AnswerBox id={`a-${question.id}`} value={q.state.draft} onChange={q.setDraft} onSend={q.answer} invalid={q.invalid} />
      <div className="ask-actions">
        <button type="button" className="btn btn-primary" aria-keyshortcuts={ariaSendKeys()} disabled={pending} onClick={q.answer}>Send answer</button>
        {holdButton}
      </div>
    </>
  );
  // The harness's own request (E1) takes one of its options and nothing else: no words, and no hold, since
  // nothing is blocked to hold.
  const extension = optionsOnly(question);
  const choices = (children?: ReactNode) => q.options && (
    <Choices
      options={q.options} onChoose={q.choose} onWords={() => q.update({ inWords: true })} inWords={q.inWords}
      disabled={pending} words={!extension}
    >
      {children}
    </Choices>
  );
  let answerUi: ReactNode = box;
  if (q.options) answerUi = q.inWords && !extension ? <>{choices()}{box}</> : choices(extension ? undefined : holdButton);
  return (
    <div className={`ask${q.isHeld ? " is-held" : ""}`} data-ask={question.id}>
      <Who plan={plan} agent={question.agent} held={q.isHeld} />
      {extension && <p className="ask-heading">{question.heading}</p>}
      {body}
      {answerUi}
      <Feedback outcome={q.command.outcome?.tone === "refused" ? q.command.outcome : null} announced={q.command.announced} />
    </div>
  );
}

/** A request, whichever kind. `onLeft` fires once a held card has faded out. */
export function AskCard({ ask, variant, onCommand, onLeft }: { ask: Ask; variant: "rail" | "widget"; onCommand: SendCommand; onLeft?: () => void }) {
  return <QuestionCard plan={ask.plan} question={ask.question} variant={variant} onCommand={onCommand} onLeft={onLeft} />;
}
