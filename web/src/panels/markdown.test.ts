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

  it("drops a <style> block with its rules, and a style attribute", () => {
    const out = html('text\n\n<style>.plan{display:none}</style>\n\n<div style="position:fixed;inset:0">fake UI</div>\n');
    expect(out.querySelector("style")).toBeNull();
    expect(out.innerHTML).not.toContain("display:none");
    expect(out.querySelector("[style]")).toBeNull();
    expect(out.textContent).toContain("fake UI");
  });

  it("drops form controls and keeps their text", () => {
    const out = html('<form action="https://evil.example/"><input name="csrf"><button>Save</button></form>');
    expect(out.querySelector("form, input, button")).toBeNull();
    expect(out.textContent).toContain("Save");
  });

  it("drops the author's classes and ids, so a document cannot borrow the page's styles", () => {
    const out = html('<div class="dialog-overlay" id="root">covers the page</div>\n\n<code class="language-ruby hljs dialog-overlay">x</code>\n');
    expect(out.querySelector(".dialog-overlay, [id]")).toBeNull();
    expect(out.querySelector("div")?.hasAttribute("class")).toBe(false);
    expect(out.querySelector("code")?.className).toBe("language-ruby");
  });

  it("keeps the classes the page adds itself: the fence's language, hljs tokens and admonitions", () => {
    const out = html("> [!NOTE]\n> Mind the gap.\n\n```ruby\ndef a = 1\n```\n\n```mermaid\ngraph TD; A-->B\n```\n");
    expect(out.querySelector("code.hljs.language-ruby .hljs-keyword")).not.toBeNull();
    expect(out.querySelector("pre code.language-mermaid")).not.toBeNull();
    expect(out.querySelector(".admonition.is-note .admonition-title")).not.toBeNull();
  });

  it("draws a task list's boxes as glyphs, not inputs", () => {
    const out = html("- [x] done\n- [ ] to do\n");
    expect(out.querySelector("input")).toBeNull();
    expect([...out.querySelectorAll("li")].map((li) => li.textContent?.trim())).toEqual(["\u2611 done", "\u2610 to do"]);
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
