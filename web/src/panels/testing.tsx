// Test support for the panels: the fixture board, a recording command callback, and a render that wraps a panel in
// its own announcer and ask store so tests never share state.
import { render, screen, type RenderOptions } from "@testing-library/react";
import { EditorView } from "@uiw/react-codemirror";
import type { ReactElement, ReactNode } from "react";
import board from "../api/fixtures/board.json";
import type { Board, Car, Command, Plan, Question, Reply } from "../api/types";
import { AsksProvider } from "./AsksProvider";
import { AnnouncerProvider } from "./feedback";

export const fixture = board as Board;
export const snapshot = fixture.me;
export const planAt = (ordinal: string): Plan => structuredClone(snapshot.plans.find((p) => p.ordinal === ordinal)!);
export const carOf = (plan: Plan, agent: string): Car => plan.cars.find((c) => c.agent === agent)!;

export const question = (over: Partial<Question> = {}): Question => ({
  id: "001.00/B1", number: 1, kind: "block", heading: "B1 Redis key layout", body: "Should Redis keys carry the checkout path?",
  agent: "backend-coder", owner: "technical", options: null, held: false, asked_at: "2026-10-13T09:00:00Z", ...over,
});

export type Sent = Omit<Command, "id">;

/** A command callback that records what it was sent and answers with `status`, or rejects when given an Error. */
export function recorder(answer: Reply["status"] | Error = "accepted", reason: string | null = null) {
  const sent: Sent[] = [];
  const onCommand = vi.fn(async (c: Sent): Promise<Reply> => {
    sent.push(c);
    if (answer instanceof Error) throw answer;
    return { id: "01J", status: answer, reason, at: "2026-10-13T09:00:00Z" };
  });
  return { sent, onCommand };
}

export function renderPanel(ui: ReactElement, { announcer = true, ...options }: RenderOptions & { announcer?: boolean } = {}) {
  const wrapper = ({ children }: { children: ReactNode }) => (
    <AsksProvider>{announcer ? <AnnouncerProvider>{children}</AnnouncerProvider> : children}</AsksProvider>
  );
  return render(ui, { wrapper, ...options });
}

/** Types into a CodeMirror editor through its own view, the way a keystroke would land. */
export function typeInEditor(container: HTMLElement, text: string) {
  const content = container.querySelector(".cm-content") as HTMLElement;
  const view = EditorView.findFromDOM(content)!;
  view.dispatch({ changes: { from: view.state.doc.length, insert: text } });
  return content;
}

/** Finds text where the panel shows it, not in the page's announcer, which repeats it. */
export const findInline = (text: string | RegExp) => screen.findByText(text, { ignore: "[data-testid=announcer], [data-testid=announcer] *, script, style" });
export const getInline = (text: string | RegExp) => screen.getByText(text, { ignore: "[data-testid=announcer], [data-testid=announcer] *, script, style" });

// axe asks a canvas for colours; jsdom has none and says so loudly. Nothing here depends on it.
HTMLCanvasElement.prototype.getContext = (() => null) as typeof HTMLCanvasElement.prototype.getContext;
// CodeMirror measures text ranges; jsdom's ranges have no geometry.
Range.prototype.getClientRects ??= () => ({ length: 0, item: () => null, [Symbol.iterator]: [][Symbol.iterator] }) as unknown as DOMRectList;
Range.prototype.getBoundingClientRect ??= () => new DOMRect();
