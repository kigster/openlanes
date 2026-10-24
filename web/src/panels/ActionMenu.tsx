// The header's Action menu: New idea opens the idea dialog; Choose an existing plan swaps the same menu for the plans
// this machine may take, with ← Back at the top. Blocked plans are offered, marked with their block emoji: the person
// adding one is right here to answer it.
import { useRef, useState, type KeyboardEvent } from "react";
import * as Menu from "@radix-ui/react-dropdown-menu";
import type { Snapshot } from "../api/types";
import { useCommand } from "./command";
import { Feedback } from "./feedback";
import { IdeaDialog } from "./IdeaDialog";
import { BLOCK_EMOJI, type SendCommand } from "./support";

export interface ActionMenuProps {
  /** Plans not complete and not claimed by any machine. */
  backlog: Snapshot["backlog"];
  onCommand: SendCommand;
  /** What was left out of the list and why, e.g. "Not listed: 001, 002 in this run; 008 on alex@build-01." */
  note?: string;
  /** Controls the idea dialog, so the page can open it from the #start hash. Uncontrolled when omitted. */
  ideaOpen?: boolean;
  onIdeaOpenChange?: (open: boolean) => void;
}

function Item({ title, sub, onSelect, className = "" }: { title: string; sub?: string; onSelect: (e: Event) => void; className?: string }) {
  return (
    <Menu.Item className={`menu-item ${className}`} onSelect={onSelect}>
      <span className="menu-title">{title}</span>
      {sub && <span className="menu-sub">{sub}</span>}
    </Menu.Item>
  );
}

export function ActionMenu({ backlog, onCommand, note, ideaOpen, onIdeaOpenChange }: ActionMenuProps) {
  const [open, setOpen] = useState(false);
  const [view, setView] = useState<"main" | "plans">("main");
  const [filter, setFilter] = useState("");
  // The idea dialog is the menu's own unless the page controls it (to open it from #start).
  const [ownIdea, setOwnIdea] = useState(false);
  const idea = ideaOpen ?? ownIdea;
  const setIdea = (next: boolean) => { setOwnIdea(next); onIdeaOpenChange?.(next); };
  const command = useCommand(onCommand);
  const filterRef = useRef<HTMLInputElement>(null);

  const onOpenChange = (next: boolean) => {
    setOpen(next);
    if (!next) { setView("main"); setFilter(""); }
  };
  const words = filter.trim().toLowerCase();
  const shown = backlog.filter((p) => !words || `${p.ordinal} ${p.title}`.toLowerCase().includes(words));
  const add = async (ordinal: string) => {
    await command.send({ kind: "add_plan", plan: ordinal, agent: null, payload: { ordinal } }, `${ordinal} added to this run.`);
  };
  // The filter box keeps its keys: letters type, they do not jump to a menu item. Down moves into the list.
  const onFilterKey = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Escape" || e.key === "Tab") return;
    e.stopPropagation();
    if (e.key === "ArrowDown") {
      e.preventDefault();
      (e.currentTarget.parentElement?.querySelector('[role="menuitem"]:not(.menu-back)') as HTMLElement | null)?.focus();
    }
  };

  return (
    <>
      <Menu.Root open={open} onOpenChange={onOpenChange}>
        <Menu.Trigger className="btn">Action <span aria-hidden="true">▾</span></Menu.Trigger>
        <Menu.Portal>
          <Menu.Content className="menu" align="end" sideOffset={6} loop>
            {view === "main" ? (
              <>
                <Item title="New idea" sub="Describe it here; plans are created for you" onSelect={() => setIdea(true)} />
                <Item
                  title="Choose an existing plan" sub="Add a plan from .plans to this run"
                  onSelect={(e) => { e.preventDefault(); setView("plans"); setTimeout(() => filterRef.current?.focus()); }}
                />
              </>
            ) : (
              <>
                <Item title="← Back" className="menu-back" onSelect={(e) => { e.preventDefault(); setView("main"); setFilter(""); }} />
                <input
                  ref={filterRef} className="menu-filter" type="search" aria-label="Filter plans" placeholder="Filter, e.g. 012 or linear"
                  value={filter} onChange={(e) => setFilter(e.target.value)} onKeyDown={onFilterKey}
                />
                {shown.map((p) => {
                  const blocked = BLOCK_EMOJI.has(p.status.emoji);
                  return (
                    <Item
                      key={p.ordinal} title={`${p.ordinal} ${p.title}`}
                      sub={`${p.status.label}, ${p.starts}${blocked ? `, blocked ${p.status.emoji}` : ""}`}
                      onSelect={() => void add(p.ordinal)}
                    />
                  );
                })}
                {backlog.length === 0 && <p className="menu-note">Nothing to add: every open plan is already being worked on.</p>}
                {backlog.length > 0 && shown.length === 0 && <p className="menu-note">No plan matches “{filter}”.</p>}
                {note && <p className="menu-note">{note}</p>}
              </>
            )}
          </Menu.Content>
        </Menu.Portal>
      </Menu.Root>
      <Feedback outcome={command.outcome} announced={command.announced} />
      <IdeaDialog open={idea} onOpenChange={setIdea} onCommand={onCommand} />
    </>
  );
}
