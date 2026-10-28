import * as panels from "./index";
import { BLOCK_EMOJI, ariaSendKeys, clock, fmt, isSendKey, modelName, sendKeys } from "./support";
import { snapshot } from "./testing";
import { modelsOf } from "../board/model";

describe("support", () => {
  it("formats tokens and time the way the board does", () => {
    expect([fmt(999), fmt(54100), fmt(1250000)]).toEqual(["999", "54.1k", "1.25M"]);
    expect([clock(42), clock(229)]).toEqual(["42s", "3m 49s"]);
    expect(modelName(modelsOf(snapshot), "claude-opus-5-5")).toBe("Opus 5.5");
    expect(modelName(modelsOf(snapshot), "gpt-x")).toBe("gpt-x");
  });

  it("names the send shortcut for the platform", () => {
    const platform = vi.spyOn(navigator, "platform", "get");
    platform.mockReturnValue("MacIntel");
    expect([sendKeys(), ariaSendKeys()]).toEqual(["⌘ Enter", "Meta+Enter"]);
    platform.mockReturnValue("Linux x86_64");
    expect([sendKeys(), ariaSendKeys()]).toEqual(["Ctrl Enter", "Control+Enter"]);
    platform.mockRestore();
    expect(isSendKey({ key: "Enter", metaKey: false, ctrlKey: true })).toBe(true);
    expect(isSendKey({ key: "Enter", metaKey: false, ctrlKey: false })).toBe(false);
  });

  it("recognises both the new and the old block emoji", () => {
    for (const e of ["⭕", "🛑", "⭕️", "🅱️", "🅱"]) expect(BLOCK_EMOJI.has(e)).toBe(true);
    expect(BLOCK_EMOJI.has("🟡")).toBe(false);
  });

  it("exports every panel from the barrel", () => {
    for (const name of ["MarkdownEditor", "NeedsYou", "UnblockWidget", "AgentDrawer", "AgentActionMenu", "ModelSelect", "ActionMenu",
      "IdeaDialog", "StopAllDialog", "HelpDialog", "AnnouncerProvider", "AsksProvider"]) {
      expect(panels).toHaveProperty(name);
    }
  });
});
