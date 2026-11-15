// Restart Control Room, Stop Local Workers and the help pill: the header's dialogs. Each brings its own trigger, so focus returns to it.
import { useEffect, useRef, useState, type ReactNode } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useCommand } from "./command";
import { Feedback } from "./feedback";
import type { SendCommand } from "./support";
import type { ConnectionState } from "../api/events";

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

/** Stop Local Workers: asks first, with the live counts, then stops every agent on this machine, then its engine and this page (W26, W29). */
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
      <Dialog.Trigger className="btn btn-alarm nav-pill" title="Stops every agent on this machine, then its engine and this page. Other machines keep running.">Stop Local Workers</Dialog.Trigger>
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

export interface RestartWebDialogProps extends Openable {
  /** The event stream's state: it drops when the server goes away and is live again once the new one answers. */
  connection: ConnectionState;
  onCommand: SendCommand;
}

/** How long a restart that was answered may go without the stream dropping before the pill stops waiting: the drop was missed, or nothing went down. */
export const RESTART_UNSEEN_MS = 30000;

/**
 * Restart Control Room: asks first, then sends `restart_web`, the command the copilot's /restart-web sends, so there
 * is one restart and two ways to ask for it. The supervisor stops this page's server, rebuilds the page when the project is OpenLanes itself and
 * starts the server again; the engine and its agents never stop.
 *
 * The engine's reply travels through the server being stopped, so it can be lost. A stream that drops while the
 * command is still unanswered is therefore read as the restart under way, not as a failure: the dialog closes and
 * the pill says Restarting… until the stream is live again.
 */
export function RestartWebDialog({ connection, onCommand, ...openable }: RestartWebDialogProps) {
  const [open, setOpen] = useOpen(openable);
  const command = useCommand(onCommand);
  const cancel = useRef<HTMLButtonElement>(null);
  // asked: answered, the server still up. down: the stream dropped, so the restart is under way.
  const [phase, setPhase] = useState<"idle" | "asked" | "down">("idle");
  const down = connection !== "live";
  useEffect(() => {
    if (down && (phase === "asked" || command.pending)) {
      setPhase("down");
      setOpen(false);
    }
    if (!down && phase === "down") setPhase("idle");
    // setOpen is a new function each render; the three values above are what this reacts to.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, down, command.pending]);
  useEffect(() => {
    if (phase !== "asked") return;
    const id = setTimeout(() => setPhase("idle"), RESTART_UNSEEN_MS);
    return () => clearTimeout(id);
  }, [phase]);
  const restart = async () => {
    const reply = await command.send({ kind: "restart_web", plan: null, agent: null, payload: {} }, "Restarting the control room. This page reconnects when it is back.");
    if (reply && reply.status !== "refused") {
      // A reply that outlived the restart finds the stream already back: there is nothing left to wait for.
      setPhase((was) => (was === "idle" && open ? "asked" : was));
      setOpen(false);
    }
  };
  const busy = phase !== "idle";
  return (
    <Dialog.Root open={open} onOpenChange={(next) => { if (next) command.setOutcome(null); setOpen(next); }}>
      <Dialog.Trigger className="btn nav-pill" disabled={busy} title="Stops this page's server and starts it again, rebuilding the page first when the project is OpenLanes itself. The engine and its agents keep working.">
        {busy ? "Restarting Control Room…" : "Restart Control Room"}
      </Dialog.Trigger>
      <Frame
        className="confirm" title="Restart the control room?"
        onOpenAutoFocus={(e) => { e.preventDefault(); cancel.current?.focus(); }}
      >
        <div className="help-body">
          <Dialog.Description>
            This stops the page's server and starts it again on the same port, rebuilding the page first when the project is OpenLanes itself. The engine and its agents keep working, and this page reconnects by itself when the server is back.
          </Dialog.Description>
          <Feedback outcome={command.outcome?.tone === "refused" ? command.outcome : null} announced={command.announced} />
        </div>
        <div className="help-foot">
          <Dialog.Close className="btn btn-quiet" ref={cancel}>Cancel</Dialog.Close>
          <button type="button" className="btn btn-primary" disabled={command.pending} onClick={restart}>Restart it</button>
        </div>
      </Frame>
    </Dialog.Root>
  );
}

export interface StopAgentDialogProps {
  /** The agent to stop, or null while nobody asked: the dialog is open exactly while this is set. */
  agent: string | null;
  plan: string;
  onConfirm: () => void;
  onCancel: () => void;
}

/**
 * Stop agent asks first: it is the one drawer action that cannot be taken back, and it sat one arrow key under Wrap
 * up. It has no trigger of its own, because the Action menu's item opens it; focus starts on Cancel, so Enter on a
 * dialog nobody read stops nothing.
 */
export function StopAgentDialog({ agent, plan, onConfirm, onCancel }: StopAgentDialogProps) {
  const cancel = useRef<HTMLButtonElement>(null);
  return (
    <Dialog.Root open={agent !== null} onOpenChange={(next) => { if (!next) onCancel(); }}>
      <Frame
        className="confirm" title={`Stop ${agent ?? "this agent"}?`}
        onOpenAutoFocus={(e) => { e.preventDefault(); cancel.current?.focus(); }}
      >
        <div className="help-body">
          <Dialog.Description>
            {agent} stops work on {plan} now and gets 60 seconds to leave a resume note. What it has not written down is lost.
            To let it finish its current step first, cancel and choose Wrap up.
          </Dialog.Description>
        </div>
        <div className="help-foot">
          <Dialog.Close className="btn btn-quiet" ref={cancel}>Cancel</Dialog.Close>
          <button type="button" className="btn btn-alarm" onClick={onConfirm}>Stop agent</button>
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
          <p><strong>Stop Local Workers</strong> stops the agents on this machine, then its engine and this page. The other machines keep running. Nothing else stops them: with every plan finished they wait here for the next one.</p>
        </div>
        <div className="help-foot"><Dialog.Close className="btn btn-primary">Got it</Dialog.Close></div>
      </Frame>
    </Dialog.Root>
  );
}
