// Messages are plain text (D10): line breaks are kept by the stylesheet, and URLs become links. Nothing else is
// rendered, so a message can never inject markup: every piece is a text node or an anchor React builds.
import type { ReactNode } from "react";

const URL = /\bhttps?:\/\/[^\s<>"]+/gi;
/** Punctuation that ends a sentence rather than the link: "see https://example.com." */
const TRAILING = /[.,;:!?'")\]]+$/;

export function linkify(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  for (const match of text.matchAll(URL)) {
    const start = match.index;
    const href = match[0].replace(TRAILING, "");
    if (start > last) out.push(text.slice(last, start));
    out.push(
      <a key={start} href={href} target="_blank" rel="noopener noreferrer">
        {href}
      </a>,
    );
    last = start + href.length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}
