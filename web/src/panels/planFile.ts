// A plan file as the popup edits it: the frontmatter block untouched, the body free. The server compares the block
// byte for byte and refuses a save that changed it, so the split keeps every byte, delimiters and newline included.
export interface SplitFile {
  /** The leading `---` block with its closing delimiter and that line's newline, or "" when the file has none. */
  frontmatter: string;
  body: string;
}

const CLOSING = /^---[ \t]*(\r?\n|$)/m;

export function splitPlanFile(text: string): SplitFile {
  const open = /^---[ \t]*\r?\n/.exec(text);
  if (!open) return { frontmatter: "", body: text };
  const rest = text.slice(open[0].length);
  const close = CLOSING.exec(rest);
  if (!close) return { frontmatter: "", body: text };
  const end = open[0].length + close.index + close[0].length;
  return { frontmatter: text.slice(0, end), body: text.slice(end) };
}

export const joinPlanFile = ({ frontmatter, body }: SplitFile): string => frontmatter + body;
