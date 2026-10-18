import { act, renderHook } from "@testing-library/react";
import type { Plan } from "../api/types";
import { FADE_MS, ROW_STAYS_MS, useLifecycle } from "./useLifecycle";
import { samplePlan, samplePr } from "./sample";

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

const merged = (ordinal: string) => samplePlan({ ordinal, pr: samplePr({ state: "merged" }) });
const approved = (ordinal: string) => samplePlan({ ordinal, pr: samplePr({ state: "approved" }) });
const finished = (ordinal: string, kind: "approved" | "merged", at = "2026-10-13T09:00:00Z") =>
  samplePlan({ ordinal, pr: samplePr({ state: kind }), finished: { kind, at } });

describe("a plan the engine marks finished", () => {
  it("keeps its row for the run, approved or merged, with no fade", () => {
    const { result } = renderHook(() => useLifecycle([finished("002.00", "merged"), finished("003.00", "approved")]));
    act(() => vi.advanceTimersByTime(ROW_STAYS_MS + FADE_MS + 60_000));
    expect(result.current.retiring.size).toBe(0);
    expect(result.current.gone.size).toBe(0);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("calls off a fade that started before the engine said finished, mid-fade too", () => {
    const { result, rerender } = renderHook(({ plans }) => useLifecycle(plans), { initialProps: { plans: [merged("002.00")] } });
    act(() => vi.advanceTimersByTime(ROW_STAYS_MS));
    expect(result.current.retiring.has("002.00")).toBe(true);
    rerender({ plans: [finished("002.00", "merged")] });
    act(() => vi.advanceTimersByTime(FADE_MS));
    expect(result.current.retiring.size).toBe(0);
    expect(result.current.gone.size).toBe(0);
  });

  it("brings back a row that had already left", () => {
    const { result, rerender } = renderHook(({ plans }) => useLifecycle(plans), { initialProps: { plans: [merged("002.00")] } });
    rerender({ plans: [] });
    expect(result.current.gone.has("002.00")).toBe(true);
    rerender({ plans: [finished("002.00", "merged")] });
    expect(result.current.gone.size).toBe(0);
  });

  it("turns into a gone pill when the snapshot drops it merged, and simply leaves when approved", () => {
    const { result, rerender } = renderHook(({ plans }) => useLifecycle(plans), {
      initialProps: { plans: [finished("002.00", "merged"), finished("003.00", "approved")] },
    });
    rerender({ plans: [] });
    expect([...result.current.gone.keys()]).toEqual(["002.00"]);
  });

  it("forgets it was merged once it turns out only approved", () => {
    const { result, rerender } = renderHook(({ plans }) => useLifecycle(plans), {
      initialProps: { plans: [finished("002.00", "merged")] },
    });
    rerender({ plans: [finished("002.00", "approved")] });
    rerender({ plans: [] });
    expect(result.current.gone.size).toBe(0);
  });

  it("numbers plans that arrive finished together in the order they finished", () => {
    const { result } = renderHook(() =>
      useLifecycle([finished("001.00", "merged", "2026-10-13T09:30:00Z"), finished("004.00", "approved", "2026-10-13T09:10:00Z")]));
    expect([...result.current.finishOrder]).toEqual([["004.00", 1], ["001.00", 2]]);
  });
});

it("keeps a merged row ten seconds, fades it for one, then remembers it as gone", () => {
  const plans: Plan[] = [samplePlan({ ordinal: "001.00" }), merged("002.00")];
  const { result } = renderHook(() => useLifecycle(plans));
  expect(result.current.finishOrder.get("002.00")).toBe(1);
  act(() => vi.advanceTimersByTime(ROW_STAYS_MS - 1));
  expect(result.current.retiring.size).toBe(0);
  act(() => vi.advanceTimersByTime(1));
  expect(result.current.retiring.has("002.00")).toBe(true);
  act(() => vi.advanceTimersByTime(FADE_MS));
  expect(result.current.retiring.size).toBe(0);
  expect(result.current.gone.get("002.00")?.plan.ordinal).toBe("002.00");
});

it("skips the fade under reduced motion", () => {
  const { result } = renderHook(() => useLifecycle([merged("002.00")], true));
  act(() => vi.advanceTimersByTime(ROW_STAYS_MS));
  act(() => vi.advanceTimersByTime(1));
  expect(result.current.gone.has("002.00")).toBe(true);
});

it("treats a merged plan the snapshot dropped as gone at once", () => {
  const { result, rerender } = renderHook(({ plans }) => useLifecycle(plans), { initialProps: { plans: [merged("003.00")] } });
  rerender({ plans: [] });
  expect(result.current.gone.has("003.00")).toBe(true);
  act(() => vi.advanceTimersByTime(ROW_STAYS_MS + FADE_MS));
  expect(result.current.gone.size).toBe(1);
});

it("numbers plans in the order they finished", () => {
  const { result, rerender } = renderHook(({ plans }) => useLifecycle(plans), {
    initialProps: { plans: [approved("005.00"), samplePlan({ ordinal: "001.00" })] },
  });
  const order = result.current.finishOrder;
  rerender({ plans: [approved("005.00"), samplePlan({ ordinal: "001.00" })] });
  expect(result.current.finishOrder).toBe(order);
  rerender({ plans: [approved("005.00"), approved("001.00")] });
  expect([...result.current.finishOrder]).toEqual([["005.00", 1], ["001.00", 2]]);
});

it("takes a purple pill off the bar once", () => {
  const { result } = renderHook(() => useLifecycle([]));
  act(() => result.current.dropFromBar("002.00"));
  const off = result.current.offBar;
  act(() => result.current.dropFromBar("002.00"));
  expect(result.current.offBar).toBe(off);
  expect(off.has("002.00")).toBe(true);
});

it("stops its timers on unmount", () => {
  const { unmount } = renderHook(() => useLifecycle([merged("002.00")]));
  unmount();
  expect(vi.getTimerCount()).toBe(0);
});
