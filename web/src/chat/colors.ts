import type { PanelColors } from "../floating";

/** D11: an orange header with black text, a white conversation in #222, a darker orange footer, whose few words are white because black on it would not read; never the copilot's blue. */
export const CHAT_COLORS: PanelColors = {
  head: "var(--chat-head)",
  headInk: "var(--chat-head-ink)",
  body: "var(--chat-body)",
  bodyInk: "var(--chat-body-ink)",
  foot: "var(--chat-foot)",
  footInk: "var(--chat-foot-ink)",
  tab: "var(--chat-head)",
  tabInk: "var(--chat-head-ink)",
};
