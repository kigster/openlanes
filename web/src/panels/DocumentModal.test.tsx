/// <reference types="node" />
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { DocumentModal } from "./DocumentModal";
import { renderMarkdown } from "./markdown";

// The real renderer, watched: the modal must not run it again for a file it has already rendered.
vi.mock("./markdown", async (original) => {
  const actual = await original<typeof import("./markdown")>();
  return { ...actual, renderMarkdown: vi.fn(actual.renderMarkdown) };
});

const SPEC = "---\ncreated: 2026-11-14\nstarts: planning\n---\n\n# Title here\n\nBody **text**.\n";
const doc = { name: "spec.md", label: "Specification" };
let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("matchMedia", (q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} }));
});
afterEach(() => vi.unstubAllGlobals());

const serve = (text: string) => fetchMock.mockResolvedValue(new Response(text, { status: 200, headers: { ETag: '"e"' } }));

describe("DocumentModal", () => {
  it("remounts the rendered preview when the theme switches, so diagrams are drawn again", async () => {
    serve(SPEC);
    document.documentElement.dataset.theme = "light";
    try {
      render(<DocumentModal ordinal="070.00" document={doc} onClose={() => {}} />);
      await screen.findByRole("heading", { name: "Title here" });
      const before = screen.getByLabelText("Specification rendered");
      await act(async () => { document.documentElement.dataset.theme = "dark"; });
      await waitFor(() => expect(screen.getByLabelText("Specification rendered")).not.toBe(before));
    } finally {
      delete document.documentElement.dataset.theme;
    }
  });

  it("renders the frontmatter as YAML and the body as markdown", async () => {
    serve(SPEC);
    render(<DocumentModal ordinal="070.00" document={doc} onClose={() => {}} />);
    expect(await screen.findByRole("heading", { name: "Title here" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "070.00 · Specification" })).toBeInTheDocument();
    const yaml = screen.getByLabelText("Frontmatter");
    expect(yaml.querySelector("code.language-yaml .hljs-attr")).not.toBeNull();
    expect(yaml.textContent).toContain("created: 2026-11-14");
  });

  it("shows no YAML block for a file without frontmatter", async () => {
    serve("# Only a body\n");
    render(<DocumentModal ordinal="070.00" document={doc} onClose={() => {}} />);
    await screen.findByRole("heading", { name: "Only a body" });
    expect(screen.queryByLabelText("Frontmatter")).toBeNull();
  });

  it("closes from the [x], the footer button and Esc", async () => {
    serve(SPEC);
    const onClose = vi.fn();
    render(<DocumentModal ordinal="070.00" document={doc} onClose={onClose} />);
    await screen.findByRole("heading", { name: "Title here" });
    await userEvent.click(screen.getByText("[x]"));
    expect(onClose).toHaveBeenCalledTimes(1);
    await userEvent.click(screen.getByText("Close"));
    expect(onClose).toHaveBeenCalledTimes(2);
    await userEvent.keyboard("{Escape}");
    expect(onClose).toHaveBeenCalledTimes(3);
  });

  it("renders the Markdown once, however often the lane re-renders it", async () => {
    serve(SPEC);
    const onClose = () => {};
    const view = render(<DocumentModal ordinal="070.00" document={doc} onClose={onClose} />);
    await screen.findByRole("heading", { name: "Title here" });
    vi.mocked(renderMarkdown).mockClear();
    for (let i = 0; i < 5; i++) view.rerender(<DocumentModal ordinal="070.00" document={{ ...doc }} onClose={() => {}} />);
    expect(renderMarkdown).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("lets the keyboard scroll the body: it is focusable and named, and the close control keeps its visible [x] in its name", async () => {
    serve(SPEC);
    render(<DocumentModal ordinal="070.00" document={doc} onClose={() => {}} />);
    await screen.findByRole("heading", { name: "Title here" });
    const body = screen.getByRole("region", { name: "Specification of 070.00" });
    expect(body).toHaveAttribute("tabindex", "0");
    expect(body).toHaveClass("document-modal-body");
    body.focus();
    expect(body).toHaveFocus();
    expect(screen.getByRole("button", { name: /\[x\]/ })).toHaveTextContent("[x]");
  });

  it("says a document is too large in the server's words for a 413", async () => {
    const error = "research.md is 61440 KB; files over 1024 KB are not shown here";
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ error }), { status: 413 }));
    render(<DocumentModal ordinal="070.00" document={doc} onClose={() => {}} />);
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent(error));
  });

  it.each([
    [413, "This document is too large to show here. Open it in an editor."],
    [415, "This document is not text, so it cannot be shown here."],
  ])("says so plainly when a %i carries no reason", async (status, message) => {
    fetchMock.mockResolvedValue(new Response("<html>refused</html>", { status }));
    render(<DocumentModal ordinal="070.00" document={doc} onClose={() => {}} />);
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent(message));
  });

  it("shows the server's reason for a 404", async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ error: "no such file" }), { status: 404 }));
    render(<DocumentModal ordinal="070.00" document={doc} onClose={() => {}} />);
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("no such file"));
  });
});

describe("panels.css", () => {
  // Read from disk: vitest runs with css: false, which turns a ?raw import of a stylesheet into an empty string.
  const css = readFileSync("src/panels/panels.css", "utf8");
  it("sizes the modal for each breakpoint", () => {
    expect(css).toMatch(/\.document-modal\s*\{[^}]*width:\s*1000px/);
    expect(css).toMatch(/@media \(max-width: 1200px\)\s*\{\s*\.document-modal\s*\{[^}]*left:\s*15%[^}]*right:\s*15%/);
    expect(css).toMatch(/@media \(max-width: 600px\)\s*\{\s*\.document-modal\s*\{[^}]*width:\s*90vw;\s*max-height:\s*90vh/);
    expect(css).toMatch(/@media \(max-width: 450px\)\s*\{\s*\.document-modal\s*\{[^}]*width:\s*calc\(100vw - 2px\)/);
  });
});
