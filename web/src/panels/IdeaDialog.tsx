// New idea (decision W19): the idea in Markdown, with the frontmatter every plan from it starts with as a form above
// the editor, never as text in it. Sending it asks the engine to create the plans (create_plans).
import { useId, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Frame } from "./dialogs";
import { useCommand } from "./command";
import { Feedback } from "./feedback";
import { MarkdownEditor } from "./MarkdownEditor";
import { IDEA_DEFAULTS, type IdeaFrontmatter } from "./frontmatter";
import { sendKeys, type SendCommand } from "./support";
import { postInterview, type InterviewQuestion } from "../api/client";

// What each choice means, shown under its control. Depth's efforts are the defaults .openlanes.yml will be able to remap (W25).
const HELP = {
  starts: {
    research: "Complex feature engaging all agents; costs the most in tokens.",
    planning: "A spec you already trust: skip research and go straight to the plan.",
    building: "A small task for a junior engineer, not a feature. Cheapest and fastest.",
  },
  research: {
    true: "Yes adds a research section to the spec. It takes more time, but provides additional context when needed.",
    false: "No sends the spec straight to the copywriter, with no additional research. For when you know what you are doing.",
    skipped: "Planning and building skip research, so there is nothing to choose.",
  },
  frontend: {
    auto: "Plans UI work automatically, when it improves the final result.",
    true: "A full-stack feature with a front-end component.",
    false: "A back-end-only feature or task.",
  },
  depth: { auto: "Maps to the model's effort; the default comes from the plan.", fast: "Low effort.", medium: "High effort.", deep: "xHigh effort." },
} as const;

type Option = readonly [value: string, text: string, dot?: string];

function Segmented({ name, legend, options, value, onChange, help, disabled = false }: {
  name: string; legend: string; options: readonly Option[]; value: string; onChange: (v: string) => void; help: string; disabled?: boolean;
}) {
  const id = useId();
  return (
    <fieldset aria-describedby={`${id}-help`}>
      <legend>{legend}</legend>
      <div className="choice">
        {options.map(([v, text, dot]) => (
          <label key={v}>
            <input type="radio" name={`${id}-${name}`} value={v} checked={value === v} disabled={disabled} onChange={() => onChange(v)} />
            <span>{dot && <i className="dot" style={{ background: dot }} />}{text}</span>
          </label>
        ))}
      </div>
      <p className="choice-help" id={`${id}-help`}>{help}</p>
    </fieldset>
  );
}

/** Starts, research, front end and depth: segmented controls in one row, each explaining its current choice. */
export function FrontmatterForm({ value, onChange }: { value: IdeaFrontmatter; onChange: (fm: IdeaFrontmatter) => void }) {
  // Research only happens when the plan starts at research; elsewhere the control shows why it is off.
  const skipped = value.starts !== "research";
  const set = (patch: Partial<IdeaFrontmatter>) => onChange({ ...value, ...patch });
  return (
    <div className="fm-form">
      <span className="lbl">Every plan from this idea starts with these settings. You can change them per plan.</span>
      <div className="fm-row">
        <Segmented
          name="starts" legend="Starts" value={value.starts} help={HELP.starts[value.starts]}
          onChange={(v) => set({ starts: v as IdeaFrontmatter["starts"] })}
          options={[["research", "Research", "var(--starts-research)"], ["planning", "Planning", "var(--starts-planning)"], ["building", "Building", "var(--starts-building)"]]}
        />
        <Segmented
          name="research" legend="Research?" value={skipped ? "false" : String(value.research)} disabled={skipped}
          help={skipped ? HELP.research.skipped : HELP.research[value.research ? "true" : "false"]}
          onChange={(v) => set({ research: v === "true" })}
          options={[["true", "Yes"], ["false", "No"]]}
        />
        <Segmented
          name="frontend" legend="Front end" value={value.frontend} help={HELP.frontend[value.frontend]}
          onChange={(v) => set({ frontend: v as IdeaFrontmatter["frontend"] })}
          options={[["auto", "Plan decides"], ["true", "Yes"], ["false", "No"]]}
        />
        <Segmented
          name="depth" legend="Depth" value={value.depth} help={HELP.depth[value.depth]}
          onChange={(v) => set({ depth: v as IdeaFrontmatter["depth"] })}
          options={[["auto", "Default"], ["fast", "Fast"], ["medium", "Medium"], ["deep", "Deep"]]}
        />
      </div>
    </div>
  );
}

export interface IdeaDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCommand: SendCommand;
}

type Decision = { question: string; answer: string };

const SUB = "Write it in Markdown, as much or as little as you like. A short idea becomes one plan; a long one goes to planner, who breaks it into plans for you to check.";

export function IdeaDialog({ open, onOpenChange, onCommand }: IdeaDialogProps) {
  const [idea, setIdea] = useState("");
  const [fm, setFm] = useState<IdeaFrontmatter>(IDEA_DEFAULTS);
  const [empty, setEmpty] = useState(false);
  const command = useCommand(onCommand);
  // The interview (M6): null before it starts, then the questions, asked one at a time, about `draft`: the idea as it
  // was when they were asked, which is the idea sent with their answers even if the editor changed since.
  const [questions, setQuestions] = useState<InterviewQuestion[] | null>(null);
  const [draft, setDraft] = useState("");
  const [answers, setAnswers] = useState<Decision[]>([]);
  const [own, setOwn] = useState("");
  const [asking, setAsking] = useState(false);
  // Each interview request holds a ticket; closing the dialog, editing the idea or skipping takes a new one, and a
  // response whose ticket is stale is dropped rather than creating a plan or showing questions nobody is waiting for.
  const ticket = useRef(0);
  // Set from the first ⌘ Enter until the plan is created or the attempt ends: state would update a render too late
  // to stop a second shortcut, and useCommand only stops overlapping sends, not a second interview.
  const busy = useRef(false);
  const reset = () => {
    ticket.current += 1;
    busy.current = false;
    setAsking(false);
    setQuestions(null);
    setAnswers([]);
    setOwn("");
  };
  const close = (next: boolean) => {
    if (!next) reset();
    onOpenChange(next);
  };
  /** @returns whether the plan was created, so a failed last answer can be sent again */
  const create = async (text: string, decisions: Decision[]) => {
    // Research is only meaningful when the plan starts at research, so the payload never says otherwise.
    const frontmatter = { ...fm, research: fm.starts === "research" && fm.research };
    const reply = await command.send(
      { kind: "create_plans", plan: null, agent: null, payload: { idea: text, frontmatter, decisions } },
      "Idea sent. Its plans join this run as they are created.",
    );
    const created = reply !== null && reply.status !== "refused";
    if (created) {
      setIdea("");
      close(false);
    }
    return created;
  };
  const go = async () => {
    if (busy.current) return;
    const text = idea.trim();
    if (!text) { setEmpty(true); return; }
    busy.current = true;
    const mine = ++ticket.current;
    setAsking(true);
    try {
      const { questions: asked } = await postInterview(text).catch(() => ({ questions: [] as InterviewQuestion[] }));
      if (ticket.current !== mine) return;
      setAsking(false);
      if (asked.length === 0) { await create(text, []); return; }
      setDraft(text);
      setAnswers([]);
      setQuestions(asked);
    } finally {
      if (ticket.current === mine) busy.current = false;
    }
  };
  // The questions are not worth waiting for: create the plan as before, and drop the interview still on its way.
  const skip = async (text: string) => {
    ticket.current += 1;
    setAsking(false);
    busy.current = true;
    try {
      await create(text, []);
    } finally {
      busy.current = false;
    }
  };
  const answer = async (text: string) => {
    if (!questions || !text.trim() || busy.current) return;
    const next = [...answers, { question: questions[answers.length].context, answer: text.trim() }];
    if (next.length < questions.length) {
      setOwn("");
      setAnswers(next);
      return;
    }
    // The last answer moves on only once the plan exists: refused, the question and a typed answer stay for a retry.
    busy.current = true;
    try {
      await create(draft, next);
    } finally {
      busy.current = false;
    }
  };
  const current = questions?.[answers.length];
  if (current && questions) {
    return (
      <Dialog.Root open={open} onOpenChange={close}>
        <Frame
          className="idea" title={`Before the spec: question ${answers.length + 1} of ${questions.length}`}
          description={<Dialog.Description asChild><p>{current.context}</p></Dialog.Description>}
        >
          <div className="start-body interview">
            {current.options.map((label, i) => (
              <button
                key={i} type="button" className={i === current.recommended ? "btn btn-recommended" : "btn"}
                disabled={command.pending} onClick={() => void answer(`${String.fromCharCode(97 + i)}) ${label}`)}
              >
                {String.fromCharCode(97 + i)}) {label}{i === current.recommended ? " (Recommended)" : ""}
              </button>
            ))}
            <input
              aria-label="Type something instead" placeholder="Type something instead" value={own}
              onChange={(e) => setOwn(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void answer(own); }}
            />
            <Feedback outcome={command.outcome?.tone === "refused" ? command.outcome : null} announced={command.announced} />
          </div>
          <div className="start-foot">
            <span className="grow">The answers go into the spec, so the agents do not stop to ask.</span>
            <button type="button" className="btn btn-quiet" disabled={command.pending} onClick={() => void skip(draft)}>Skip the interview</button>
          </div>
        </Frame>
      </Dialog.Root>
    );
  }
  return (
    <Dialog.Root open={open} onOpenChange={close}>
      <Frame
        className="idea" title="What is the product or feature you'd like to build?"
        description={<Dialog.Description asChild><p>{empty ? "Write the idea first. A sentence is enough." : SUB}</p></Dialog.Description>}
      >
        <div className="start-body">
          <FrontmatterForm value={fm} onChange={setFm} />
          <MarkdownEditor
            value={idea} onChange={(v) => { setEmpty(false); setIdea(v); if (asking) reset(); }} onSubmit={go} label="Your idea, in Markdown"
            previewLabel="Preview of your idea" invalid={empty} autoFocus height="min(52vh, 460px)"
            placeholder={`# A household budget app\n\nFamilies track shared spending...\n\n## Accounts\n- Import bank statements\n\n${sendKeys()} sends it.`}
          />
          <Feedback outcome={command.outcome?.tone === "refused" ? command.outcome : null} announced={command.announced} />
        </div>
        <div className="start-foot">
          <span className="grow">This creates the plans and adds them to this run.</span>
          <Dialog.Close className="btn btn-quiet">Cancel</Dialog.Close>
          {asking && <button type="button" className="btn btn-quiet" disabled={command.pending} onClick={() => void skip(idea.trim())}>Skip the questions</button>}
          <button type="button" className="btn btn-primary" disabled={command.pending || asking} onClick={go}>{asking ? "Preparing questions…" : "Break it into plans"}</button>
        </div>
      </Frame>
    </Dialog.Root>
  );
}
