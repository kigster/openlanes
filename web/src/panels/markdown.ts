// Markdown to safe HTML, in the mockup's order: marked parses, DOMPurify strips anything that could run, then
// highlight.js colours each fenced block in the language its fence names. Gruvbox colours its classes (panels.css).
import { marked } from "marked";
import DOMPurify from "dompurify";
import hljs from "highlight.js/lib/common";

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
  const html = marked.parse(text, { async: false, gfm: true });
  const fragment = DOMPurify.sanitize(html, { RETURN_DOM_FRAGMENT: true });
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
