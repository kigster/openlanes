import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { ModelSelect } from "./ModelSelect";
import { carOf, planAt, recorder, renderPanel, snapshot } from "./testing";
import { modelsOf } from "../board/model";

const plan = planAt("005.00");
const car = carOf(plan, "staff-reviewer"); // on Sonnet 5.5

describe("ModelSelect on a car", () => {
  it("names itself and passes axe", async () => {
    const { container } = render(<ModelSelect plan="005.00" car={car} models={modelsOf(snapshot)} mode="next" onCommand={recorder().onCommand} />);
    expect(screen.getByRole("combobox", { name: "Model for staff-reviewer" })).toHaveTextContent("Sonnet 5.5");
    expect(await axe(container)).toHaveNoViolations();
  });

  it("queues an upgrade for the next round with set_model and shows it in bold", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const onOutcome = vi.fn();
    renderPanel(<ModelSelect plan="005.00" car={car} models={modelsOf(snapshot)} mode="next" onCommand={onCommand} onOutcome={onOutcome} />);
    await user.click(screen.getByRole("combobox"));
    await user.click(await screen.findByRole("option", { name: "Opus 5.5" }));
    await waitFor(() => expect(sent).toEqual([{ kind: "set_model", plan: "005.00", agent: "staff-reviewer", payload: { model: "claude-opus-5-5" } }]));
    const trigger = screen.getByRole("combobox", { name: "Model for staff-reviewer, Opus 5.5 from its next round" });
    expect(trigger).toHaveClass("is-changed");
    expect(onOutcome).toHaveBeenCalledWith("Upgrade to Opus 5.5 queued; it applies from the next round.", false);
    expect(screen.getByTestId("announcer")).toHaveTextContent("Upgrade to Opus 5.5 queued");
  });

  it("says Downgrade, and Staying when it goes back", async () => {
    const user = userEvent.setup();
    const onOutcome = vi.fn();
    renderPanel(<ModelSelect plan="005.00" car={car} models={modelsOf(snapshot)} mode="next" onCommand={recorder().onCommand} onOutcome={onOutcome} />);
    await user.click(screen.getByRole("combobox"));
    await user.click(await screen.findByRole("option", { name: "Haiku 5.5" }));
    await waitFor(() => expect(onOutcome).toHaveBeenLastCalledWith("Downgrade to Haiku 5.5 queued; it applies from the next round.", false));
    await user.click(screen.getByRole("combobox"));
    await user.click(await screen.findByRole("option", { name: "Sonnet 5.5" }));
    await waitFor(() => expect(onOutcome).toHaveBeenLastCalledWith("Staying on Sonnet 5.5.", false));
    expect(screen.getByRole("combobox")).not.toHaveClass("is-changed");
  });

  it("puts the old choice back when the engine refuses", async () => {
    const user = userEvent.setup();
    const onOutcome = vi.fn();
    renderPanel(<ModelSelect plan="005.00" car={car} models={modelsOf(snapshot)} mode="next" onCommand={recorder("refused", "unknown model").onCommand} onOutcome={onOutcome} />);
    await user.click(screen.getByRole("combobox"));
    await user.click(await screen.findByRole("option", { name: "Opus 5.5" }));
    await waitFor(() => expect(onOutcome).toHaveBeenCalledWith("Refused: unknown model.", true));
    expect(screen.getByRole("combobox")).toHaveTextContent("Sonnet 5.5");
  });
});

describe("ModelSelect in the drawer", () => {
  it("ignores choosing the model it already runs, and reports a refused switch", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder("refused", "busy");
    const onOutcome = vi.fn();
    renderPanel(<><span id="lbl">Model</span><ModelSelect plan="005.00" car={car} models={modelsOf(snapshot)} mode="now" labelledBy="lbl" onCommand={onCommand} onOutcome={onOutcome} /></>);
    await user.click(screen.getByRole("combobox", { name: "Model" }));
    await user.click(await screen.findByRole("option", { name: "Haiku 5.5" }));
    await waitFor(() => expect(onOutcome).toHaveBeenCalledWith("Refused: busy.", true));
    expect(sent).toHaveLength(1);
  });
});
