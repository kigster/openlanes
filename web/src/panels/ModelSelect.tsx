// The model picker. On a car it queues a model for the agent's next round (set_model, W24); in the drawer the same
// component switches the agent now and compacts first (switch_model, W27).
import { useState } from "react";
import * as Select from "@radix-ui/react-select";
import type { Car, ModelChoice } from "../api/types";
import { refusal, useCommand } from "./command";
import { modelName, type SendCommand } from "./support";

export interface ModelSelectProps {
  plan: string;
  car: Car;
  /** The models of the adapter the car runs on, most capable first (plan 040, D13). */
  models: ModelChoice[];
  /** Why that adapter cannot take an agent now ("pi: no model provider signed in"); the picker is disabled and says so
   * (D11). Null or omitted when it can. */
  unavailable?: string | null;
  /** "next" queues for the next round (a car); "now" switches it now (the drawer). */
  mode: "next" | "now";
  onCommand: SendCommand;
  /** The visible label's id, when the drawer labels it; a car's picker names itself. */
  labelledBy?: string;
  /** Called with what the reply said, so the drawer can put it in the transcript. */
  onOutcome?: (said: string, refused: boolean) => void;
}

export function ModelSelect({ plan, car, models, mode, onCommand, labelledBy, onOutcome, unavailable = null }: ModelSelectProps) {
  const command = useCommand(onCommand);
  // A queued model shows in bold until the next round picks it up; the snapshot's model is the one running now.
  const [queued, setQueued] = useState<string | null>(null);
  // The queue empties once the snapshot runs the queued model, or when the picker is handed another car.
  const [seen, setSeen] = useState(car.key);
  if (seen !== car.key) {
    setSeen(car.key);
    setQueued(null);
  } else if (queued !== null && queued === car.model) {
    setQueued(null);
  }
  const value = mode === "next" ? queued ?? car.model : car.model;
  const rank = (id: string) => models.findIndex((m) => m.id === id);

  const change = async (to: string) => {
    if (mode === "now") {
      if (to === car.model) return;
      const said = `Switching from ${modelName(models, car.model)} to ${modelName(models, to)}; it runs /compact first.`;
      // No reply means another send was still in flight, and that one reports for both.
      const reply = await command.send({ kind: "switch_model", plan, agent: car.agent, payload: { model: to } }, said);
      if (reply) onOutcome?.(reply.status === "refused" ? refusal(reply) : said, reply.status === "refused");
      return;
    }
    const staying = to === car.model;
    const said = staying ? `Staying on ${modelName(models, car.model)}.`
      : `${rank(to) < rank(car.model) ? "Upgrade" : "Downgrade"} to ${modelName(models, to)} queued; it applies from the next round.`;
    const previous = queued;
    setQueued(staying ? null : to);
    const reply = await command.send({ kind: "set_model", plan, agent: car.agent, payload: { model: to } }, said);
    const refused = reply?.status === "refused";
    if (!reply || refused) setQueued(previous);
    if (reply) onOutcome?.(refused ? refusal(reply) : said, refused);
  };

  const changed = mode === "next" && queued !== null;
  return (
    <Select.Root value={value} onValueChange={change} disabled={command.pending || unavailable !== null}>
      <Select.Trigger
        className={`model-trigger${mode === "now" ? " is-field" : ""}${changed ? " is-changed" : ""}`}
        aria-label={labelledBy ? undefined
          : `Model for ${car.agent}${changed ? `, ${modelName(models, value)} from its next round` : ""}${unavailable ? `, unavailable: ${unavailable}` : ""}`}
        aria-labelledby={labelledBy}
        title={unavailable ?? (mode === "next" ? "Model for its next round" : undefined)}
      >
        <Select.Value />
        <Select.Icon aria-hidden="true">▾</Select.Icon>
      </Select.Trigger>
      <Select.Portal>
        <Select.Content className="model-content" position="popper" sideOffset={4}>
          <Select.Viewport>
            {models.map((m) => (
              <Select.Item key={m.id} value={m.id} className="model-item">
                <Select.ItemIndicator className="model-check">✓</Select.ItemIndicator>
                <Select.ItemText>{m.label}</Select.ItemText>
              </Select.Item>
            ))}
          </Select.Viewport>
        </Select.Content>
      </Select.Portal>
    </Select.Root>
  );
}
