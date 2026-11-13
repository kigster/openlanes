import { act, renderHook } from "@testing-library/react";
import { FILTER_KEY, useStateFilter } from "./useStateFilter";

const keys = ["building", "approved", "abandoned"];
beforeEach(() => localStorage.clear());

it("checks every state but the archived states by default", () => {
  const { result } = renderHook(() => useStateFilter(keys));
  expect([...result.current.checked]).toEqual(["building"]);
});

it("remembers a choice across mounts", () => {
  const first = renderHook(() => useStateFilter(keys));
  act(() => first.result.current.toggle("approved"));
  first.unmount();
  const again = renderHook(() => useStateFilter(keys));
  expect([...again.result.current.checked].sort()).toEqual(["approved", "building"]);
  act(() => again.result.current.toggle("building"));
  expect([...again.result.current.checked]).toEqual(["approved"]);
});

it("falls back to the default on a value nobody wrote", () => {
  localStorage.setItem(FILTER_KEY, "{not json");
  expect([...renderHook(() => useStateFilter(keys)).result.current.checked]).toEqual(["building"]);
});
