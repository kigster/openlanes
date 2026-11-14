/// <reference types="node" />
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { DocumentModal } from "./DocumentModal";

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
    expect(css).toMatch(/\.document-modal\s*\{[^}]*width:\s*min\(1000px, 70vw\)/);
    expect(css).toMatch(/@media \(max-width: 1200px\)\s*\{\s*\.document-modal\s*\{[^}]*left:\s*15%[^}]*right:\s*15%/);
    expect(css).toMatch(/@media \(max-width: 600px\)\s*\{\s*\.document-modal\s*\{[^}]*width:\s*90vw;\s*max-height:\s*90vh/);
    expect(css).toMatch(/@media \(max-width: 450px\)\s*\{\s*\.document-modal\s*\{[^}]*width:\s*calc\(100vw - 2px\)/);
  });
});
