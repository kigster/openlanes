import { act, fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import type { Bomb } from "../api/types";
import { COPILOT_OPEN_EVENT, type CopilotOpenRequest } from "../copilot/useCopilot";
import { BombNotice } from "./BombNotice";
import { findInline, recorder, renderPanel } from "./testing";

const bomb = (over: Partial<Bomb> = {}): Bomb => ({
  plan: "009.00",
  slug: "plan-aging-and-bombs",
  blocked_md: "# Blocked\n\n## B1 Which deadline?\n\nShould a plan age by **wall clock** or by rounds?",
  blocked_since: "2026-10-13T09:00:00Z",
  resume_until: null,
  ...over,
});

const notice = (plan: string) => screen.getByRole("region", { name: new RegExp(`^${plan.replace(".", "\\.")} `) });

describe("BombNotice", () => {
  it("renders nothing when there are no bombs", () => {
    const { container } = renderPanel(<BombNotice bombs={[]} onCommand={recorder().onCommand} />);
    expect(container.querySelector(".bombs")).toBeNull();
    expect(screen.queryByRole("region")).toBeNull();
  });

  it("renders one notice per bomb, its blocked.md as Markdown, accessibly", async () => {
    const two = [bomb(), bomb({ plan: "010.00", slug: "second-plan", blocked_md: "## B1 Other\n\nAnything?" })];
    const { container } = renderPanel(<BombNotice bombs={two} onCommand={recorder().onCommand} />);
    expect(screen.getAllByRole("region")).toHaveLength(2);
    const first = notice("009.00");
    expect(within(first).getByRole("heading", { name: "B1 Which deadline?" })).toBeInTheDocument();
    expect(within(first).getByText("wall clock").tagName).toBe("STRONG");
    expect(within(notice("010.00")).getByRole("textbox", { name: "Your answer to 010.00" })).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("keeps Respond disabled while the box is empty, then sends respond with the text and clears the box", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<BombNotice bombs={[bomb()]} onCommand={onCommand} />);
    const respond = screen.getByRole("button", { name: "Respond" });
    expect(respond).toBeDisabled();
    const box = screen.getByRole("textbox", { name: "Your answer to 009.00" });
    await user.type(box, "   ");
    expect(respond).toBeDisabled();
    await user.clear(box);
    await user.type(box, "Wall clock, 48 hours.");
    await user.click(respond);
    expect(sent).toEqual([{ kind: "respond", plan: "009.00", agent: null, payload: { text: "Wall clock, 48 hours." } }]);
    expect(await findInline("Answer sent to 009.00.")).toBeInTheDocument();
    expect(box).toHaveValue("");
  });

  it("sends respond with Ctrl Enter from the box", async () => {
    const { sent, onCommand } = recorder();
    renderPanel(<BombNotice bombs={[bomb()]} onCommand={onCommand} />);
    const box = screen.getByRole("textbox", { name: "Your answer to 009.00" });
    fireEvent.change(box, { target: { value: "Rounds." } });
    await act(async () => {
      fireEvent.keyDown(box, { key: "Enter", ctrlKey: true });
    });
    expect(sent).toEqual([{ kind: "respond", plan: "009.00", agent: null, payload: { text: "Rounds." } }]);
  });

  it("keeps the text and shows the reason when respond is refused", async () => {
    const user = userEvent.setup();
    const { onCommand } = recorder("refused", "every question already has an answer");
    renderPanel(<BombNotice bombs={[bomb()]} onCommand={onCommand} />);
    const box = screen.getByRole("textbox", { name: "Your answer to 009.00" });
    await user.type(box, "Late answer");
    await user.click(screen.getByRole("button", { name: "Respond" }));
    expect(await findInline("Refused: every question already has an answer.")).toBeInTheDocument();
    expect(box).toHaveValue("Late answer");
  });

  it("Pause and Discuss sends pause_discuss, then opens the copilot on that plan", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const opened: CopilotOpenRequest[] = [];
    const listen = (e: Event) => opened.push((e as CustomEvent<CopilotOpenRequest>).detail);
    window.addEventListener(COPILOT_OPEN_EVENT, listen);
    try {
      renderPanel(<BombNotice bombs={[bomb()]} onCommand={onCommand} />);
      await user.click(screen.getByRole("button", { name: "Pause and Discuss" }));
      expect(sent).toEqual([{ kind: "pause_discuss", plan: "009.00", agent: null, payload: {} }]);
      await waitFor(() => expect(opened).toHaveLength(1));
      expect(opened[0].plan).toBe("009.00");
      expect(opened[0].text).toContain("009.00 (plan-aging-and-bombs)");
    } finally {
      window.removeEventListener(COPILOT_OPEN_EVENT, listen);
    }
  });

  it("Resume anyway sends resume_anyway", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<BombNotice bombs={[bomb()]} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: "Resume anyway for 24 h" }));
    expect(sent).toEqual([{ kind: "resume_anyway", plan: "009.00", agent: null, payload: {} }]);
    expect(await findInline("009.00 carries on for 24 hours.")).toBeInTheDocument();
  });

  it("shows when the halt is lifted until instead of the button while resume_until is ahead", async () => {
    const { container } = renderPanel(<BombNotice bombs={[bomb({ resume_until: "2099-01-02T03:04:00Z" })]} onCommand={recorder().onCommand} />);
    expect(screen.queryByRole("button", { name: "Resume anyway for 24 h" })).toBeNull();
    expect(screen.getByText(/^halt lifted until /)).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("offers the button again once resume_until has passed", () => {
    renderPanel(<BombNotice bombs={[bomb({ resume_until: "2020-01-01T00:00:00Z" })]} onCommand={recorder().onCommand} />);
    expect(screen.getByRole("button", { name: "Resume anyway for 24 h" })).toBeInTheDocument();
    expect(screen.queryByText(/halt lifted/)).toBeNull();
  });
});
