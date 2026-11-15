import { act, renderHook } from "@testing-library/react";
import { FILTER_KEY, useStateFilter } from "./useStateFilter";

const states = [
  { key: "building", emoji: "🟡", name: "Building", archived: false },
  { key: "approved", emoji: "✅", name: "Approved", archived: true },
  { key: "abandoned", emoji: "🚮", name: "Abandoned", archived: true },
];
beforeEach(() => localStorage.clear());

it("checks every state the server does not flag archived by default", () => {
  const { result } = renderHook(() => useStateFilter(states));
  expect([...result.current.checked]).toEqual(["building"]);
});

it("remembers a choice across mounts", () => {
  const first = renderHook(() => useStateFilter(states));
  act(() => first.result.current.toggle("approved"));
  first.unmount();
  const again = renderHook(() => useStateFilter(states));
  expect([...again.result.current.checked].sort()).toEqual(["approved", "building"]);
  act(() => again.result.current.toggle("building"));
  expect([...again.result.current.checked]).toEqual(["approved"]);
});

it("falls back to the default on a value nobody wrote", () => {
  localStorage.setItem(FILTER_KEY, "{not json");
  expect([...renderHook(() => useStateFilter(states)).result.current.checked]).toEqual(["building"]);
});
