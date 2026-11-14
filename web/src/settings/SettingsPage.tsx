import { useMemo, useState } from "react";
import { SettingsRefusalError, SettingsValidationError, useSaveSettings, useSettings } from "../api/settings";
import type { SettingsDocument, SettingsFieldError, SettingsValues } from "../api/types";
import { Pane } from "./Pane";
import { errorsByPath, panesOf, prune, sameValues, setAt, shownPaths } from "./model";
import "./settings.css";

/** The project's `.openlanes.yml`, as one form: a pane per section, saved, committed and pushed to main in one click. */
export function SettingsPage() {
  const { data, error, isLoading } = useSettings();
  const save = useSaveSettings();
  // Every post-save message lives out here: the refetch after a save remounts the form, and each one must survive that alike.
  const [messages, setMessages] = useState<Messages>(NONE);
  if (error) return <main className="set-page is-error" role="alert">Could not load the settings: {error.message}</main>;
  if (isLoading || !data) return <main className="set-page" aria-busy="true">Loading settings…</main>;
  // Keyed by etag: a save that moved the file resets the draft to what the server now holds.
  return <SettingsForm key={data.etag} doc={data} save={save} messages={messages} setMessages={setMessages} />;
}

interface Messages {
  note: string | null;
  refusal: string | null;
  fieldErrors: SettingsFieldError[];
}

const NONE: Messages = { note: null, refusal: null, fieldErrors: [] };

interface FormProps {
  doc: SettingsDocument;
  save: ReturnType<typeof useSaveSettings>;
  messages: Messages;
  setMessages: (messages: Messages) => void;
}

function SettingsForm({ doc, save, messages, setMessages }: FormProps) {
  const { note, refusal, fieldErrors } = messages;
  const [draft, setDraft] = useState<SettingsValues>(doc.values);
  const panes = useMemo(() => panesOf(doc), [doc]);
  const errors = useMemo(() => errorsByPath(fieldErrors), [fieldErrors]);
  const shown = useMemo(() => shownPaths(panes), [panes]);
  const orphans = fieldErrors.filter(e => !shown.has(e.path.join(".")));

  const onSave = () => {
    if (sameValues(draft, doc.values)) {
      setMessages({ ...NONE, note: "Nothing changed, so nothing was written." });
      return;
    }
    setMessages(NONE);
    save.mutate(
      { values: prune(draft) as SettingsValues, etag: doc.etag },
      {
        onSuccess: r => setMessages({ ...NONE, note: r.changed ? `Saved and pushed to ${doc.branch ?? "main"} as ${r.commit.slice(0, 7)}.` : "Nothing changed, so nothing was written." }),
        onError: e => {
          if (e instanceof SettingsValidationError) setMessages({ ...NONE, fieldErrors: e.errors });
          else setMessages({ ...NONE, refusal: e instanceof SettingsRefusalError ? e.reason : e.message });
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
