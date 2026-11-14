import { describe, expect, it } from "vitest";
import { renderFrontmatter, renderMarkdown } from "./markdown";

const html = (text: string) => {
  const div = document.createElement("div");
  div.innerHTML = renderMarkdown(text);
  return div;
};

describe("renderMarkdown", () => {
  it.each(["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"])("turns [!%s] into an admonition", (kind) => {
    const box = html(`> [!${kind}]\n> Body text\n`).querySelector(`.admonition.is-${kind.toLowerCase()}`);
    expect(box).not.toBeNull();
    expect(box?.querySelector(".admonition-title")?.textContent).toBe(kind.charAt(0) + kind.slice(1).toLowerCase());
    expect(box?.textContent).toContain("Body text");
    expect(box?.textContent).not.toContain("[!");
  });

  it("leaves an ordinary blockquote alone", () => {
    const out = html("> just a quote\n");
    expect(out.querySelector("blockquote")).not.toBeNull();
    expect(out.querySelector(".admonition")).toBeNull();
  });

  it("keeps links opening safely and code highlighted", () => {
    const out = html("[a](https://x.test)\n\n```ruby\nputs 1\n```\n");
    expect(out.querySelector("a")?.getAttribute("rel")).toBe("noopener noreferrer");
    expect(out.querySelector("code.hljs")).not.toBeNull();
  });

  it("strips script", () => {
    expect(renderMarkdown("<script>alert(1)</script>hi")).not.toContain("<script");
  });
});

describe("renderFrontmatter", () => {
  it("highlights the block as YAML without its delimiters", () => {
    const out = renderFrontmatter("---\ncreated: 2026-11-14\nfrontend: false\n---\n");
    expect(out).toContain('class="hljs language-yaml"');
    expect(out).toContain("hljs-attr");
    expect(out).not.toContain("---");
  });
});
