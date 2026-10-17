// Where each agent of a plan stood when its round ended early: its own `state resume` record, or the harness's when it
// died first. Read-only, like the engine's side of it: a person reads this; nothing on the page acts on it.
import * as Tooltip from "@radix-ui/react-tooltip";
import { type ReactNode, useId } from "react";
import type { LastKnown } from "../api/types";

const SOURCE: Record<LastKnown["source"], string> = { agent: "agent", harness: "harness" };

/**
 * The status, with the agent's next step as its tooltip. The trigger takes focus so a keyboard opens it too, and the
 * step is also sr-only text in the cell, since a screen reader reading the table never opens a tooltip.
 */
function Status({ entry }: { entry: LastKnown }) {
  if (!entry.next_step) return <>{entry.status}</>;
  return (
    <Tooltip.Root>
      <Tooltip.Trigger asChild>
        <span className="lk-next" tabIndex={0}>
          {entry.status}
          <span className="sr-only">. Next step: {entry.next_step}</span>
        </span>
      </Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content className="tooltip" side="top" sideOffset={6}>
          Next step: {entry.next_step}
          <Tooltip.Arrow className="tooltip-arrow" />
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
}

// One row per field, one column per agent: a drawer is narrow, and a plan rarely has more than two or three agents
// with a record, so agents across and fields down fits where six columns of fields did not. The next step is the
// status's tooltip rather than a row of its own.
const FIELDS: { label: string; value: (e: LastKnown) => ReactNode }[] = [
  { label: "Source", value: (e) => SOURCE[e.source] ?? e.source },
  { label: "Round", value: (e) => e.round },
  { label: "Status", value: (e) => <Status entry={e} /> },
  { label: "Note", value: (e) => e.note ?? "—" },
];

export function LastKnownTable({ entries }: { entries: LastKnown[] }) {
  const title = useId();
  if (entries.length === 0) return null;
  return (
    <Tooltip.Provider delayDuration={300}>
      <section className="d-last-known" aria-labelledby={title}>
        <h3 id={title}>Last known state</h3>
        <table>
          <thead>
            <tr>
              <th scope="col">Agent</th>
              {entries.map((e) => <th key={e.agent} scope="col">{e.agent}</th>)}
            </tr>
          </thead>
          <tbody>
            {FIELDS.map((f) => (
              <tr key={f.label}>
                <th scope="row">{f.label}</th>
                {entries.map((e) => <td key={e.agent}>{f.value(e)}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </Tooltip.Provider>
  );
}
