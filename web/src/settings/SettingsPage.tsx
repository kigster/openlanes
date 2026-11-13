import { useMemo, useState } from "react";
import { SettingsRefusalError, SettingsValidationError, useSaveSettings, useSettings } from "../api/settings";
import type { SettingsDocument, SettingsFieldError, SettingsValues } from "../api/types";
import { Pane } from "./Pane";
import { errorsByPath, panesOf, prune, sameValues, setAt } from "./model";
import "./settings.css";

/** The project's `.openlanes.yml`, as one form: a pane per section, saved, committed and pushed to main in one click. */
export function SettingsPage() {
  const { data, error, isLoading } = useSettings();
  const save = useSaveSettings();
  const [note, setNote] = useState<string | null>(null);
  if (error) return <main className="set-page is-error" role="alert">Could not load the settings: {error.message}</main>;
  if (isLoading || !data) return <main className="set-page" aria-busy="true">Loading settings…</main>;
  // Keyed by etag: a save that moved the file resets the draft to what the server now holds. The mutation and the note
  // live out here, since the refetch after a save remounts the form and would drop both.
  return <SettingsForm key={data.etag} doc={data} save={save} note={note} setNote={setNote} />;
}

interface FormProps {
  doc: SettingsDocument;
  save: ReturnType<typeof useSaveSettings>;
  note: string | null;
  setNote: (note: string | null) => void;
}

function SettingsForm({ doc, save, note, setNote }: FormProps) {
  const [draft, setDraft] = useState<SettingsValues>(doc.values);
  const [fieldErrors, setFieldErrors] = useState<SettingsFieldError[]>([]);
  const [refusal, setRefusal] = useState<string | null>(null);
  const panes = useMemo(() => panesOf(doc), [doc]);
  const errors = useMemo(() => errorsByPath(fieldErrors), [fieldErrors]);
  const shown = new Set(panes.flatMap(function collect(p): string[] { return [...p.fields.map(f => f.path.join(".")), ...p.children.flatMap(collect)]; }));
  const orphans = fieldErrors.filter(e => !shown.has(e.path.join(".")));

  const onSave = () => {
    setRefusal(null);
    setFieldErrors([]);
    if (sameValues(draft, doc.values)) {
      setNote("Nothing changed, so nothing was written.");
      return;
    }
    setNote(null);
    save.mutate(
      { values: prune(draft) as SettingsValues, etag: doc.etag },
      {
        onSuccess: r => setNote(r.changed ? `Saved and pushed to ${doc.branch ?? "main"} as ${r.commit.slice(0, 7)}.` : "Nothing changed, so nothing was written."),
        onError: e => {
          if (e instanceof SettingsValidationError) setFieldErrors(e.errors);
          else if (e instanceof SettingsRefusalError) setRefusal(e.reason);
          else setRefusal(e.message);
        },
      },
    );
  };

  return (
    <main className="set-page">
      <h1>Project settings</h1>
      {panes.map(p => (
        <Pane key={p.id} pane={p} values={draft} defaults={doc.defaults} errors={errors} onChange={(path, v) => setDraft(d => setAt(d, path, v))} />
      ))}
      {orphans.length > 0 && (
        <ul className="set-error" role="alert">
          {orphans.map(e => <li key={e.path.join(".")}>{e.path.join(".")}: {e.message}</li>)}
        </ul>
      )}
      <div className="set-actions">
        <button type="button" className="set-save" disabled={save.isPending} onClick={onSave}>Save, commit and push to main</button>
        <span className="set-note">Writes .openlanes.yml, commits it alone and pushes {doc.branch ?? "main"}.</span>
        {refusal && <p className="set-refusal" role="alert">{refusal}</p>}
        {note && <p className="set-status" role="status">{note}</p>}
      </div>
    </main>
  );
}
