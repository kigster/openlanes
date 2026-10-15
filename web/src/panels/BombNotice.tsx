// The bomb notices (plan 009): one full-width notice above the board for every plan that sat blocked past its deadline
// and is now halted. Its blocked.md on the left, and on the right the three ways out: respond, pause and talk it over
// with the copilot, or lift the halt for a day.
import { useId, useState } from "react";
import type { Bomb } from "../api/types";
import { openCopilot } from "../copilot/useCopilot";
import { useCommand } from "./command";
import { Feedback } from "./feedback";
import { renderMarkdown } from "./markdown";
import { ariaSendKeys, isSendKey, sendKeys, type SendCommand } from "./support";

export interface BombNoticeProps {
  /** `snapshot.bombs` of this machine: [] draws nothing. */
  bombs: Bomb[];
  onCommand: SendCommand;
}

const when = (iso: string): string =>
  new Date(iso).toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

/** The halt is lifted while `resume_until` is still ahead of now. */
const lifted = (bomb: Bomb, now: number = Date.now()): boolean =>
  bomb.resume_until !== null && new Date(bomb.resume_until).getTime() > now;

export function BombNotice({ bombs, onCommand }: BombNoticeProps) {
  if (bombs.length === 0) return null;
  return (
    <div className="bombs">
      {bombs.map(bomb => (
        <OneBomb key={bomb.plan} bomb={bomb} onCommand={onCommand} />
      ))}
    </div>
  );
}

function OneBomb({ bomb, onCommand }: { bomb: Bomb; onCommand: SendCommand }) {
  const id = useId();
  const { send, outcome, pending, announced } = useCommand(onCommand);
  const [text, setText] = useState("");
  const plan = bomb.plan;
  const answer = text.trim();

  const respond = async () => {
    if (!answer || pending) return;
    const reply = await send({ kind: "respond", plan, agent: null, payload: { text: answer } }, `Answer sent to ${plan}.`);
    if (reply && reply.status !== "refused") setText("");
  };
  const discuss = async () => {
    await send({ kind: "pause_discuss", plan, agent: null, payload: {} }, `${plan}'s agents are held while you talk it over.`);
    openCopilot({ plan, text: `About ${plan} (${bomb.slug}), halted on a bomb: ` });
  };
  const resume = () =>
    void send({ kind: "resume_anyway", plan, agent: null, payload: {} }, `${plan} carries on for 24 hours.`);

  return (
    <section className="bomb" aria-labelledby={`${id}-title`} data-plan={plan}>
      <h2 id={`${id}-title`} className="bomb-title">
        <span aria-hidden="true">💣 </span>
        {plan} {bomb.slug} is halted
        <span className="bomb-since"> blocked since {when(bomb.blocked_since)}</span>
      </h2>
      <div className="bomb-body">
        <div className="ask-text bomb-blocked" dangerouslySetInnerHTML={{ __html: renderMarkdown(bomb.blocked_md) }} />
        <form
          className="bomb-answer"
          onSubmit={e => {
            e.preventDefault();
            void respond();
          }}
        >
          <label htmlFor={`${id}-answer`}>Your answer to {plan}</label>
          <textarea
            id={`${id}-answer`}
            value={text}
            placeholder={`Answer the open question. ${sendKeys()} sends it.`}
            aria-keyshortcuts={ariaSendKeys()}
            onChange={e => setText(e.target.value)}
            onKeyDown={e => {
              if (isSendKey(e)) {
                e.preventDefault();
                void respond();
              }
            }}
          />
          <div className="ask-actions">
            <button type="submit" className="btn btn-primary" disabled={!answer || pending}>
              Respond
            </button>
            <button type="button" className="btn" disabled={pending} onClick={() => void discuss()}>
              Pause and Discuss
            </button>
            {lifted(bomb) ? (
              <p className="bomb-lifted">halt lifted until {when(bomb.resume_until!)}</p>
            ) : (
              <button type="button" className="btn btn-quiet" disabled={pending} onClick={resume}>
                Resume anyway for 24 h
              </button>
            )}
          </div>
          <Feedback outcome={outcome} announced={announced} />
        </form>
      </div>
    </section>
  );
}
