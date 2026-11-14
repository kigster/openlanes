// Draws the ```mermaid fences of a rendered document. Mermaid is imported when a document first has one, so the board's
// bundle does not carry it until a modal opens.
let counter = 0;

/** Replaces each `pre code.language-mermaid` under `root` with its SVG; a diagram that will not draw keeps its source. */
export async function renderMermaid(root: HTMLElement, dark = false): Promise<void> {
  const blocks = [...root.querySelectorAll<HTMLElement>("pre code.language-mermaid")];
  if (blocks.length === 0) return;
  const { default: mermaid } = await import("mermaid");
  mermaid.initialize({ startOnLoad: false, theme: dark ? "dark" : "default", securityLevel: "strict" });
  for (const code of blocks) {
    const pre = code.closest("pre");
    if (!pre) continue;
    try {
      const { svg } = await mermaid.render(`mermaid-${counter++}`, code.textContent ?? "");
      const holder = document.createElement("div");
      holder.className = "mermaid-diagram";
      holder.innerHTML = svg;
      pre.replaceWith(holder);
    } catch (error) {
      const note = document.createElement("p");
      note.className = "mermaid-error";
      note.textContent = `Could not draw this diagram: ${error instanceof Error ? error.message : "invalid syntax"}`;
      pre.after(note);
    }
  }
}
