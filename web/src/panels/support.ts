// Small helpers every panel shares: the command callback's type, number formats and the send shortcut's wording.
import type { Command, ModelChoice, Question, Reply } from "../api/types";

/** What every panel calls to act. The page mints the id; the panel names the rest. */
export type SendCommand = (command: Omit<Command, "id">) => Promise<Reply>;

/** Tokens the way the board prints them: 54.1k, 1.25M. */
export const fmt = (n: number): string =>
  n >= 1e6 ? `${(n / 1e6).toFixed(2)}M` : n >= 1e3 ? `${(n / 1e3).toFixed(1)}k` : String(n);

/** Elapsed seconds: 42s, 3m 49s. */
export const clock = (s: number): string =>
  s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`;

/** A model id's label from the snapshot's list, or the id itself when the list does not know it. */
export const modelName = (models: ModelChoice[], id: string): string => models.find((m) => m.id === id)?.label ?? id;

const isMac = (): boolean => /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
/** How the send shortcut is written in placeholders: ⌘ Enter on a Mac, Ctrl Enter elsewhere. */
export const sendKeys = (): string => (isMac() ? "⌘ Enter" : "Ctrl Enter");
/** The same shortcut for aria-keyshortcuts. */
export const ariaSendKeys = (): string => (isMac() ? "Meta+Enter" : "Control+Enter");
/** True for ⌘ Enter or Ctrl Enter, from any text box. */
export const isSendKey = (e: { key: string; metaKey: boolean; ctrlKey: boolean }): boolean =>
  e.key === "Enter" && (e.metaKey || e.ctrlKey);

/** The B<n> a command addresses a question by; the question's id carries the plan too. */
export const questionRef = (q: Question): string => `B${q.number}`;

/**
 * The red block emoji the status bar uses, so the backlog marks blocked plans the same way. Holds the single
 * code point forms and the old VS16 forms, so a snapshot from an unmigrated repo still marks blocked plans.
 */
export const BLOCK_EMOJI = new Set(["⭕", "🛑", "⭕️", "🅱️", "🅱"]);
