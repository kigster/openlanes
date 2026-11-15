import { beforeEach, describe, expect, it, vi } from "vitest";

// A plain function, not a vi.fn that throws: vitest reports a spy's thrown error as the test's own failure.
const calls: string[] = [];
let outcome: "svg" | "error" = "svg";
const initialize = vi.fn();
// As Mermaid does: the drawing node goes onto <body> first, and a parse error throws without taking it away.
const render = async (id: string, source: string) => {
  calls.push(source);
  const temp = document.createElement("div");
  temp.id = `d${id}`;
  document.body.append(temp);
  if (outcome === "error") throw new Error("Parse error");
  temp.remove();
  return { svg: "<svg id='x'></svg>" };
};
vi.mock("mermaid", () => ({ default: { initialize, render: (id: string, source: string) => render(id, source) } }));

import { renderMermaid } from "./mermaid";

const rootWith = (source: string) => {
  const root = document.createElement("div");
  root.innerHTML = `<pre><code class="language-mermaid">${source}</code></pre>`;
  return root;
};

beforeEach(() => { calls.length = 0; outcome = "svg"; });

describe("renderMermaid", () => {
  it("replaces a fence with its svg", async () => {
    const root = rootWith("graph TD; A-->B");
    await renderMermaid(root);
    expect(root.querySelector(".mermaid-diagram svg")).not.toBeNull();
    expect(root.querySelector("pre")).toBeNull();
  });

  it("keeps the source and says why when the diagram is bad", async () => {
    outcome = "error";
    const root = rootWith("nonsense");
    await renderMermaid(root, true);
    expect(root.querySelector("pre")?.textContent).toBe("nonsense");
    expect(root.querySelector(".mermaid-error")?.textContent).toContain("Parse error");
  });

  it("leaves nothing in <body> after diagrams that will not draw", async () => {
    outcome = "error";
    const before = document.body.childElementCount;
    for (let i = 0; i < 3; i++) await renderMermaid(rootWith("nonsense"));
    expect(document.body.childElementCount).toBe(before);
  });

  it("tells Mermaid not to draw its own error diagram", async () => {
    await renderMermaid(rootWith("graph TD; A-->B"));
    expect(initialize).toHaveBeenLastCalledWith(expect.objectContaining({ suppressErrorRendering: true, securityLevel: "strict" }));
  });

  it("does not load mermaid for a document without a diagram", async () => {
    const root = document.createElement("div");
    root.innerHTML = "<p>hi</p>";
    await renderMermaid(root);
    expect(calls).toEqual([]);
  });
});
