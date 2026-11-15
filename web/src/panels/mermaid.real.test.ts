// The real Mermaid, not the double in mermaid.test.ts: only it can show that a fence which fails to parse leaves
// nothing behind in <body> (issue 254).
import { describe, expect, it } from "vitest";
import { renderMermaid } from "./mermaid";

const rootWith = (source: string) => {
  const root = document.createElement("div");
  root.innerHTML = `<pre><code class="language-mermaid">${source}</code></pre>`;
  document.body.append(root);
  return root;
};

describe("renderMermaid with the real Mermaid", () => {
  it("adds no children to <body> for fences that fail to parse", async () => {
    const roots = [rootWith("graph TD; A--"), rootWith("graph TD; A--"), rootWith("not a diagram at all")];
    const before = document.body.childElementCount;
    for (const root of roots) await renderMermaid(root, root === roots[1]);
    expect(document.body.childElementCount).toBe(before);
    expect(document.querySelector("[id^=dmermaid-]")).toBeNull();
    for (const root of roots) {
      expect(root.querySelector("pre")).not.toBeNull();
      expect(root.querySelector(".mermaid-error")?.textContent).toMatch(/^Could not draw this diagram: /);
    }
    roots.forEach((root) => root.remove());
  }, 30_000);
});
