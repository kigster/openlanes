import { act, renderHook } from "@testing-library/react";
import { NAV_HIDDEN_KEY, useNavHidden } from "./useNavHidden";

afterEach(() => {
  localStorage.clear();
  vi.restoreAllMocks();
});

it("starts shown, and remembers hidden in this browser", () => {
  const { result } = renderHook(() => useNavHidden());
  const first = result.current.hidden;
  act(() => result.current.toggle());
  const stored = localStorage.getItem(NAV_HIDDEN_KEY);
  const reloaded = renderHook(() => useNavHidden()).result.current.hidden;
  act(() => result.current.toggle());
  expect([first, stored, reloaded, result.current.hidden, localStorage.getItem(NAV_HIDDEN_KEY)]).toEqual([false, "on", true, false, "off"]);
});

it("works for the visit in a private window, where storage throws", () => {
  vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
    throw new Error("denied");
  });
  vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
    throw new Error("denied");
  });
  const { result } = renderHook(() => useNavHidden());
  act(() => result.current.toggle());
  expect(result.current.hidden).toBe(true);
});
