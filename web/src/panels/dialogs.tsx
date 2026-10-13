// Stop All Local and the help pill: the header's two dialogs. Each brings its own trigger, so focus returns to it.
import { useRef, useState, type ReactNode } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useCommand } from "./command";
import { Feedback } from "./feedback";
import type { SendCommand } from "./support";

/** Controlled when `open` is given; otherwise the trigger opens it. */
interface Openable {
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

function useOpen({ open, onOpenChange }: Openable): [boolean, (open: boolean) => void] {
  const [own, setOwn] = useState(false);
  return [open ?? own, (next) => { setOwn(next); onOpenChange?.(next); }];
}

export function Frame({ className, title, description, children, onOpenAutoFocus, onCloseAutoFocus }: {
  className: string; title: string; description?: ReactNode; children: ReactNode; onOpenAutoFocus?: (e: Event) => void;
  onCloseAutoFocus?: (e: Event) => void;
}) {
  return (
    <Dialog.Portal>
      <Dialog.Overlay className="dialog-overlay" />
      <Dialog.Content className={`start ${className}`} onOpenAutoFocus={onOpenAutoFocus} onCloseAutoFocus={onCloseAutoFocus}>
        <div className="start-head">
          <Dialog.Title asChild><h2>{title}</h2></Dialog.Title>
          {description}
        </div>
        {children}
      </Dialog.Content>
    </Dialog.Portal>
  );
}

export interface StopAllDialogProps extends Openable {
  /** Agents working on this machine now. */
  agents: number;
  /** Plans they are working on. */
  plans: number;
  onCommand: SendCommand;
}

/** Stop All Local: asks first, with the live counts, then stops every agent on this machine, then its engine and this page (W26, W29). */
export function StopAllDialog({ agents, plans, onCommand, ...openable }: StopAllDialogProps) {
  const [open, setOpen] = useOpen(openable);
  const command = useCommand(onCommand);
  const cancel = useRef<HTMLButtonElement>(null);
  const stop = async () => {
    const reply = await command.send({ kind: "stop_all", plan: null, agent: null, payload: {} }, `Stopping ${agents} agents on this machine.`);
    if (reply && reply.status !== "refused") setOpen(false);
  };
  return (
    <Dialog.Root open={open} onOpenChange={(next) => { if (next) command.setOutcome(null); setOpen(next); }}>
      <Dialog.Trigger className="btn btn-alarm" title="Stops every agent on this machine, then its engine and this page. Other machines keep running.">Stop All Local</Dialog.Trigger>
      <Frame
        className="confirm" title="Stop all local agents?"
        onOpenAutoFocus={(e) => { e.preventDefault(); cancel.current?.focus(); }}
      >
        <div className="help-body">
          <Dialog.Description>
            Are you sure you want to shut down {agents} agents currently working on {plans} plans, and then the engine and this page? This only affects this machine.
          </Dialog.Description>
          <Feedback outcome={command.outcome?.tone === "refused" ? command.outcome : null} announced={command.announced} />
        </div>
        <div className="help-foot">
          <Dialog.Close className="btn btn-quiet" ref={cancel}>Cancel</Dialog.Close>
          <button type="button" className="btn btn-alarm" disabled={command.pending} onClick={stop}>Stop them</button>
        </div>
      </Frame>
    </Dialog.Root>
  );
}

/** The round ? pill and the help dialog. The copy is the mockup's draft, word for word, until the author replaces it. */
export function HelpDialog(openable: Openable) {
  const [open, setOpen] = useOpen(openable);
  return (
    <Dialog.Root open={open} onOpenChange={setOpen}>
      <Dialog.Trigger className="btn btn-quiet help-pill" aria-label="How this works">?</Dialog.Trigger>
      <Frame className="help" title="How this works" description={<Dialog.Description asChild><p>Draft copy, to be replaced by the author's.</p></Dialog.Description>}>
        <div className="help-body">
          <p><strong>This is a distributed software factory.</strong> Every machine that runs openlanes on this repository and points at the same Redis works on the same set of plans, side by side.</p>
          <p><strong>You join by sharing <code>$REDIS_URL</code>.</strong> There is no other mechanism: no invitation, no accounts. Anyone who connects to that Redis from a clone of the same GitHub repository is in, and shows up here as a machine of their own.</p>
          <p><strong>Nobody can be kept out or kicked out.</strong> This is not a policy enforcement system. It assumes everyone around is friendly: other machines are shown read only, and a plan one machine is working on is left alone by the rest, by agreement, not by force.</p>
          <p><strong>Stop All Local</strong> stops the agents on this machine, then its engine and this page. The other machines keep running. Nothing else stops them: with every plan finished they wait here for the next one.</p>
        </div>
        <div className="help-foot"><Dialog.Close className="btn btn-primary">Got it</Dialog.Close></div>
      </Frame>
    </Dialog.Root>
  );
}
