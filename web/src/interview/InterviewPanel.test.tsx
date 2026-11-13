import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { afterEach, expect, it, vi } from "vitest";
import * as api from "../api/interview";
import type { InterviewTurn } from "../api/types";
import { AskCard } from "../panels/AskCard";
import { AsksProvider } from "../panels/AsksProvider";
import { AnnouncerProvider } from "../panels/feedback";
import { planAt, question, recorder } from "../panels/testing";
import { InterviewPanel } from "./InterviewPanel";

vi.mock("../api/interview", async importOriginal => ({
  ...(await importOriginal<typeof import("../api/interview")>()),
  fetchInterview: vi.fn(),
  sendInterview: vi.fn(),
}));

const at = "2026-11-13T00:00:00Z";
const ask: InterviewTurn = {
  id: "t1", from: "unblocker", kind: "question", text: "Should the suite ignore the outage spec?", at,
  options: [{ label: "Yes, skip it", recommended: true }, { label: "No, fix it first", recommended: false }],
};
const decision: InterviewTurn = { id: "t3", from: "unblocker", kind: "decision", text: "So we skip it.", at: "2026-11-13T00:00:09Z", answer: "a) Yes, skip it" };

function wrap(children: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={client}><AsksProvider><AnnouncerProvider>{children}</AnnouncerProvider></AsksProvider></QueryClientProvider>);
}

afterEach(() => vi.resetAllMocks());

it("shows the question with its recommended option marked, and sends a button's words", async () => {
  vi.mocked(api.fetchInterview).mockResolvedValue([ask]);
  vi.mocked(api.sendInterview).mockResolvedValue({ id: "u1", from: "you", kind: "text", text: "Yes, skip it", at });
  wrap(<InterviewPanel plan="001.00" question={question()} onCommand={recorder().onCommand} onClose={() => {}} />);
  expect(await screen.findByText("Should the suite ignore the outage spec?")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /Yes, skip it/ })).toHaveClass("is-recommended");
  await userEvent.click(screen.getByRole("button", { name: /Yes, skip it/ }));
  expect(api.sendInterview).toHaveBeenCalledWith("001.00", 1, "Yes, skip it");
  expect(await screen.findByText("You")).toBeInTheDocument();
});

it("sends a typed reply", async () => {
  vi.mocked(api.fetchInterview).mockResolvedValue([ask]);
  vi.mocked(api.sendInterview).mockResolvedValue({ id: "u1", from: "you", kind: "text", text: "not sure", at });
  wrap(<InterviewPanel plan="001.00" question={question()} onCommand={recorder().onCommand} onClose={() => {}} />);
  await screen.findByText(ask.text);
  await userEvent.type(screen.getByLabelText("Your reply"), "not sure");
  await userEvent.click(screen.getByRole("button", { name: "Send" }));
  expect(api.sendInterview).toHaveBeenCalledWith("001.00", 1, "not sure");
});

it("shows the decision with Confirm, which confirms and closes", async () => {
  vi.mocked(api.fetchInterview).mockResolvedValue([ask, decision]);
  const { onCommand, sent } = recorder("done");
  const onClose = vi.fn();
  wrap(<InterviewPanel plan="001.00" question={question()} onCommand={onCommand} onClose={onClose} />);
  expect(await screen.findByText("a) Yes, skip it")).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: "Confirm" }));
  expect(sent[0]).toMatchObject({ kind: "confirm_interview", plan: "001.00", payload: { question: "1", turn: "t3" } });
  await waitFor(() => expect(onClose).toHaveBeenCalled());
});

it("says why a confirm was refused and stays open", async () => {
  vi.mocked(api.fetchInterview).mockResolvedValue([decision]);
  const onClose = vi.fn();
  wrap(<InterviewPanel plan="001.00" question={question()} onCommand={recorder("refused", "already answered").onCommand} onClose={onClose} />);
  await userEvent.click(await screen.findByRole("button", { name: "Confirm" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("already answered");
  expect(onClose).not.toHaveBeenCalled();
});

it("opens from Talk it through, and closing it leaves the card's buttons usable", async () => {
  vi.mocked(api.fetchInterview).mockResolvedValue([ask]);
  const plan = planAt("001.00");
  const q = question({ options: [{ letter: "a", label: "Yes", answer: "a) Yes", recommended: true }, { letter: "b", label: "No", answer: "b) No", recommended: false }] });
  const { onCommand, sent } = recorder();
  wrap(<AskCard ask={{ kind: "question", id: q.id, plan, question: q }} variant="rail" onCommand={onCommand} />);
  await userEvent.click(screen.getByRole("button", { name: "Talk it through" }));
  expect(await screen.findByText(ask.text)).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: "Answer on the card instead" }));
  expect(screen.queryByText(ask.text)).toBeNull();
  await userEvent.click(screen.getByRole("button", { name: /Yes/ }));
  expect(sent[0]).toMatchObject({ kind: "answer", payload: { text: "a) Yes" } });
});
