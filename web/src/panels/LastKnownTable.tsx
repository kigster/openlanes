// Where each agent of a plan stood when its round ended early: its own `state resume` record, or the harness's when it
// died first. Read-only, like the engine's side of it: a person reads this; nothing on the page acts on it.
import { useId } from "react";
import type { LastKnown } from "../api/types";

const SOURCE: Record<LastKnown["source"], string> = { agent: "agent", harness: "harness" };

export function LastKnownTable({ entries }: { entries: LastKnown[] }) {
  const title = useId();
  if (entries.length === 0) return null;
  return (
    <section className="d-last-known" aria-labelledby={title}>
      <h3 id={title}>Last known state</h3>
      <table>
        <thead>
          <tr>
            <th scope="col">Agent</th>
            <th scope="col">Source</th>
            <th scope="col">Round</th>
            <th scope="col">Status</th>
            <th scope="col">Next step</th>
            <th scope="col">Note</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((e) => (
            <tr key={e.agent}>
              <th scope="row">{e.agent}</th>
              <td>{SOURCE[e.source] ?? e.source}</td>
              <td>{e.round}</td>
              <td>{e.status}</td>
              <td>{e.next_step ?? "—"}</td>
              <td>{e.note ?? "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
