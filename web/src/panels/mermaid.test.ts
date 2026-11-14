import { beforeEach, describe, expect, it, vi } from "vitest";

// A plain function, not a vi.fn that throws: vitest reports a spy's thrown error as the test's own failure.
const calls: string[] = [];
let outcome: "svg" | "error" = "svg";
const render = async (_id: string, source: string) => {
  calls.push(source);
  if (outcome === "error") throw new Error("Parse error");
  return { svg: "<svg id='x'></svg>" };
};
vi.mock("mermaid", () => ({ default: { initialize: vi.fn(), render: (id: string, source: string) => render(id, source) } }));

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

  it("does not load mermaid for a document without a diagram", async () => {
    const root = document.createElement("div");
    root.innerHTML = "<p>hi</p>";
    await renderMermaid(root);
    expect(calls).toEqual([]);
  });
});
