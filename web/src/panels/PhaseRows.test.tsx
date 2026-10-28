import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { axe } from "vitest-axe";
import { PhaseRows } from "./PhaseRows";
import { chosenPhases, IDEA_DEFAULTS, walked, type IdeaFrontmatter, type PhaseCatalog } from "./frontmatter";
import { snapshot } from "./testing";

const catalog: PhaseCatalog = snapshot;

function Harness({ start = IDEA_DEFAULTS, onForm }: { start?: IdeaFrontmatter; onForm?: (fm: IdeaFrontmatter) => void }) {
  const [fm, setFm] = useState(start);
  return <PhaseRows catalog={catalog} value={fm} onChange={(next) => { setFm(next); onForm?.(next); }} />;
}

describe("PhaseRows (plan 040, D10)", () => {
  it("lists one row per phase the plan walks, and passes axe", async () => {
    const { container } = render(<Harness start={{ ...IDEA_DEFAULTS, starts: "building" }} />);
    expect(screen.getAllByRole("combobox", { name: /^Adapter for / }).map(s => s.getAttribute("aria-label")))
      .toEqual(["Adapter for build", "Adapter for review", "Adapter for verification", "Adapter for completion"]);
    expect(await axe(container)).toHaveNoViolations();
  });

  it("lists an unusable adapter disabled, with its reason (D11)", () => {
    render(<Harness />);
    const pi = screen.getAllByRole("option", { name: /^pi: / })[0];
    expect(pi).toBeDisabled();
    expect(screen.getByText(/Not available on this machine: pi: /)).toBeInTheDocument();
  });

  it("offers the chosen adapter's models, and resets the model when the adapter changes", async () => {
    const user = userEvent.setup();
    const onForm = vi.fn();
    render(<Harness start={{ ...IDEA_DEFAULTS, starts: "building" }} onForm={onForm} />);
    const model = screen.getByRole("combobox", { name: "Model for build" });
    expect(model).toBeDisabled();
    await user.selectOptions(screen.getByRole("combobox", { name: "Adapter for build" }), "codex");
    const codex = snapshot.adapters.find(a => a.name === "codex")!.models[0];
    await user.selectOptions(model, codex.id);
    expect(onForm).toHaveBeenLastCalledWith(expect.objectContaining({ phases: { build: { adapter: "codex", model: codex.id } } }));
    await user.selectOptions(screen.getByRole("combobox", { name: "Adapter for build" }), "claude");
    expect(onForm).toHaveBeenLastCalledWith(expect.objectContaining({ phases: { build: { adapter: "claude", model: "" } } }));
  });

  it("draws nothing for a lane with no phases", () => {
    const { container } = render(<PhaseRows catalog={{ ...catalog, phases: { ...catalog.phases, building: [] } }}
      value={{ ...IDEA_DEFAULTS, starts: "building" }} onChange={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe("walked and chosenPhases", () => {
  it("leaves out the front end when the form turns it off", () => {
    expect(walked(catalog, { ...IDEA_DEFAULTS, frontend: "false" }).map(r => r.phase)).not.toContain("frontend");
    expect(walked(catalog, IDEA_DEFAULTS).map(r => r.phase)).toContain("frontend");
  });

  it("names only what was chosen, for phases the plan walks", () => {
    const fm: IdeaFrontmatter = {
      ...IDEA_DEFAULTS, starts: "building",
      phases: { build: { adapter: "codex", model: "" }, review: { adapter: "", model: "" }, research: { adapter: "pi", model: "" } },
    };
    expect(chosenPhases(catalog, fm)).toEqual({ build: { adapter: "codex" } });
  });
});
