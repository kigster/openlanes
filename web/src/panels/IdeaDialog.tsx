// New idea (decision W19): the idea in Markdown, with the frontmatter every plan from it starts with as a form above
// the editor, never as text in it. Sending it asks the engine to create the plans (create_plans).
import { useId, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Frame } from "./dialogs";
import { useCommand } from "./command";
import { Feedback } from "./feedback";
import { MarkdownEditor } from "./MarkdownEditor";
import { IDEA_DEFAULTS, type IdeaFrontmatter } from "./frontmatter";
import { sendKeys, type SendCommand } from "./support";

// What each choice means, shown under its control. Depth's efforts are the defaults .openlanes.yml will be able to remap (W25).
const HELP = {
  lane: {
    full: "Complex feature engaging all agents; costs the most in tokens.",
    plan: "A spec you already trust: skip research and go straight to the plan.",
    quick: "A small task for a junior engineer, not a feature. Cheapest and fastest.",
  },
  research: {
    true: "Yes adds a research section to the spec. It takes more time, but provides additional context when needed.",
    false: "No sends the spec straight to the copywriter, with no additional research. For when you know what you are doing.",
    skipped: "The plan and quick lanes skip research, so there is nothing to choose.",
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

/** Lane, research, front end and depth: segmented controls in one row, each explaining its current choice. */
export function FrontmatterForm({ value, onChange }: { value: IdeaFrontmatter; onChange: (fm: IdeaFrontmatter) => void }) {
  // Research only happens on the full lane; elsewhere the control shows why it is off.
  const skipped = value.lane !== "full";
  const set = (patch: Partial<IdeaFrontmatter>) => onChange({ ...value, ...patch });
  return (
    <div className="fm-form">
      <span className="lbl">Every plan from this idea starts with these settings. You can change them per plan.</span>
      <div className="fm-row">
        <Segmented
          name="lane" legend="Lane" value={value.lane} help={HELP.lane[value.lane]}
          onChange={(v) => set({ lane: v as IdeaFrontmatter["lane"] })}
          options={[["full", "Full", "var(--lane-full)"], ["plan", "Plan", "var(--lane-plan)"], ["quick", "Quick", "var(--lane-quick)"]]}
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

const SUB = "Write it in Markdown, as much or as little as you like. A short idea becomes one plan; a long one goes to palpatine-planner, who breaks it into plans for you to check.";

export function IdeaDialog({ open, onOpenChange, onCommand }: IdeaDialogProps) {
  const [idea, setIdea] = useState("");
  const [fm, setFm] = useState<IdeaFrontmatter>(IDEA_DEFAULTS);
  const [empty, setEmpty] = useState(false);
  const command = useCommand(onCommand);
  const go = async () => {
    if (!idea.trim()) { setEmpty(true); return; }
    // Research is only meaningful on the full lane, so the payload never says otherwise.
    const frontmatter = { ...fm, research: fm.lane === "full" && fm.research };
    const reply = await command.send(
      { kind: "create_plans", plan: null, agent: null, payload: { idea: idea.trim(), frontmatter } },
      "Idea sent. Its plans join this run as they are created.",
    );
    if (reply && reply.status !== "refused") {
      setIdea("");
      onOpenChange(false);
    }
  };
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Frame
        className="idea" title="What is the product or feature you'd like to build?"
        description={<Dialog.Description asChild><p>{empty ? "Write the idea first. A sentence is enough." : SUB}</p></Dialog.Description>}
      >
        <div className="start-body">
          <FrontmatterForm value={fm} onChange={setFm} />
          <MarkdownEditor
            value={idea} onChange={(v) => { setEmpty(false); setIdea(v); }} onSubmit={go} label="Your idea, in Markdown"
            previewLabel="Preview of your idea" invalid={empty} autoFocus height="min(52vh, 460px)"
            placeholder={`# A household budget app\n\nFamilies track shared spending...\n\n## Accounts\n- Import bank statements\n\n${sendKeys()} sends it.`}
          />
          <Feedback outcome={command.outcome?.tone === "refused" ? command.outcome : null} announced={command.announced} />
        </div>
        <div className="start-foot">
          <span className="grow">This creates the plans and adds them to this run.</span>
          <Dialog.Close className="btn btn-quiet">Cancel</Dialog.Close>
          <button type="button" className="btn btn-primary" disabled={command.pending} onClick={go}>Break it into plans</button>
        </div>
      </Frame>
    </Dialog.Root>
  );
}
