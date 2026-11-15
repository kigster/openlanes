// Markdown to safe HTML, in the mockup's order: marked parses, DOMPurify strips anything that could run, then
// highlight.js colours each fenced block in the language its fence names. Gruvbox colours its classes (panels.css).
import { Marked } from "marked";
import DOMPurify from "dompurify";
import hljs from "highlight.js/lib/common";

// A plan file is written by agents and by whoever can push to the repository, so its HTML is not the page's own.
// Nothing that runs survives DOMPurify's defaults; these go further and keep a document from restyling the page
// (<style>, style=), posing as its controls (<form>, <input>, <button>) or taking an id the page looks up.
const SANITIZE = {
  RETURN_DOM_FRAGMENT: true as const,
  FORBID_TAGS: ["style", "form", "input", "button"],
  FORBID_ATTR: ["style", "id"],
};

// The one class the renderer needs from the Markdown: marked names a fence's language on its <code>. Every other
// class is the author's, and `class="dialog-overlay"` would borrow the page's own stylesheet to cover it. The classes
// the page adds itself (hljs-*, admonition) are added after this runs.
const FENCE_CLASS = /^language-[\w+#.-]+$/;

/** Drops every class but a fence's language. */
function declass(fragment: DocumentFragment): void {
  for (const node of fragment.querySelectorAll("[class]")) {
    const kept = node.tagName === "CODE" ? [...node.classList].filter((c) => FENCE_CLASS.test(c)) : [];
    if (kept.length) node.className = kept.join(" ");
    else node.removeAttribute("class");
  }
}

// A task list's box is drawn as a glyph: marked would emit an <input>, which the sanitizer no longer lets through.
const markdown = new Marked({ gfm: true, renderer: { checkbox: ({ checked }) => (checked ? "\u2611" : "\u2610") } });

const ADMONITION = /^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*\r?\n?/i;

/** A blockquote opening with [!NOTE] (or TIP, IMPORTANT, WARNING, CAUTION) becomes a titled box; any other is left alone. */
function admonish(fragment: DocumentFragment): void {
  for (const quote of fragment.querySelectorAll("blockquote")) {
    const first = quote.firstElementChild;
    const hit = first?.tagName === "P" ? ADMONITION.exec(first.innerHTML) : null;
    if (!first || !hit) continue;
    const kind = hit[1].toLowerCase();
    first.innerHTML = first.innerHTML.slice(hit[0].length);
    if (!first.textContent?.trim() && first.children.length === 0) first.remove();
    const box = document.createElement("div");
    box.className = `admonition is-${kind}`;
    const title = document.createElement("p");
    title.className = "admonition-title";
    title.textContent = kind.charAt(0).toUpperCase() + kind.slice(1);
    box.append(title, ...quote.childNodes);
    quote.replaceWith(box);
  }
}

/** The raw frontmatter block, without its `---` lines, as a YAML-highlighted code block. */
export function renderFrontmatter(yaml: string): string {
  const inner = yaml.replace(/^---[ \t]*\r?\n/, "").replace(/(^|\r?\n)---[ \t]*\r?\n?$/, "");
  const highlighted = hljs.highlight(inner, { language: "yaml", ignoreIllegals: true }).value;
  return `<pre><code class="hljs language-yaml">${highlighted}</code></pre>`;
}

export function renderMarkdown(text: string): string {
  const html = markdown.parse(text, { async: false });
  const fragment = DOMPurify.sanitize(html, SANITIZE);
  declass(fragment);
  for (const a of fragment.querySelectorAll("a")) {
    a.target = "_blank";
    a.rel = "noopener noreferrer";
  }
  for (const code of fragment.querySelectorAll("pre code")) {
    const lang = [...code.classList].find((c) => c.startsWith("language-"))?.slice(9);
    if (lang && hljs.getLanguage(lang)) {
      code.innerHTML = hljs.highlight(code.textContent ?? "", { language: lang, ignoreIllegals: true }).value;
      code.classList.add("hljs");
    }
  }
  admonish(fragment);
  const out = document.createElement("div");
  out.append(fragment);
  return out.innerHTML;
}
