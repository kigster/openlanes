import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import type { PlanReview as Review } from "../api/types";
import { planAt, recorder, renderPanel } from "../panels/testing";
import { PlanReview } from "./PlanReview";

const review = (ruling: "strike" | null = null): Review => ({
  diff: { stat: " a.rb | 2 +-", patch: "diff --git a/a.rb b/a.rb", truncated: false },
  findings: [{ id: "F1", reviewer: "staff-reviewer", severity: "major", file: "a.rb", line: 3, text: "Missing guard", ruling }],
});
const json = (b: unknown) => new Response(JSON.stringify(b), { status: 200 });

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => { fetchMock = vi.fn(); vi.stubGlobal("fetch", fetchMock); });
afterEach(() => vi.unstubAllGlobals());

function mount(onCommand = recorder().onCommand) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const Wrap = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return renderPanel(<Wrap><PlanReview plan={planAt("005.00")} onCommand={onCommand} /></Wrap>);
}

it("reads nothing until opened, then shows the stat, a patch toggle and the findings", async () => {
  const user = userEvent.setup();
  fetchMock.mockResolvedValue(json(review()));
  mount();
  expect(fetchMock).not.toHaveBeenCalled();
  await user.click(screen.getByRole("button", { name: "Review" }));
  expect(await screen.findByText(/a\.rb \| 2/)).toBeInTheDocument();
  expect(fetchMock.mock.calls[0][0]).toBe("/api/plans/005.00/review");
  expect(screen.getByText("Missing guard")).toBeInTheDocument();
  expect(screen.getByText("diff --git a/a.rb b/a.rb")).not.toBeVisible();
  await user.click(screen.getByRole("button", { name: "Show patch" }));
  expect(screen.getByText("diff --git a/a.rb b/a.rb")).toBeVisible();
});

it("sends rule_finding on Strike and shows the ruling the engine kept", async () => {
  const user = userEvent.setup();
  const { sent, onCommand } = recorder("done", "F1 strike");
  fetchMock.mockResolvedValueOnce(json(review())).mockResolvedValue(json(review("strike")));
  mount(onCommand);
  await user.click(screen.getByRole("button", { name: "Review" }));
  await user.click(await screen.findByRole("button", { name: /Strike/ }));
  await waitFor(() => expect(sent).toEqual([{ kind: "rule_finding", plan: "005.00", agent: null, payload: { finding: "F1", verdict: "strike" } }]));
  expect(await screen.findByText("Struck")).toBeInTheDocument();
});

it("shows a refusal and says when the review cannot be read", async () => {
  const user = userEvent.setup();
  fetchMock.mockResolvedValue(new Response("", { status: 404 }));
  mount();
  await user.click(screen.getByRole("button", { name: "Review" }));
  expect(await screen.findByText("The review could not be read.")).toBeInTheDocument();
});

it("accepts a finding and shows a refused reply", async () => {
  const user = userEvent.setup();
  fetchMock.mockResolvedValue(json(review()));
  const { sent, onCommand } = recorder("refused", "unknown finding");
  mount(onCommand);
  await user.click(screen.getByRole("button", { name: "Review" }));
  await user.click(await screen.findByRole("button", { name: /Accept/ }));
  expect(sent[0].payload).toEqual({ finding: "F1", verdict: "accept" });
  expect((await screen.findAllByText(/Refused: unknown finding/)).length).toBeGreaterThan(0);
});
