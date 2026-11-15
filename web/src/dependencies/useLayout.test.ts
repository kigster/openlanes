import { act, renderHook } from "@testing-library/react";
import { LAYOUT_KEY, useLayout } from "./useLayout";

beforeEach(() => localStorage.clear());
afterEach(() => vi.restoreAllMocks());

it("starts on Adaptive, and keeps a pick for the next visit", () => {
  const { result, unmount } = renderHook(() => useLayout());
  expect(result.current.layout).toBe("adaptive");
  act(() => result.current.pick("circular"));
  expect([result.current.layout, localStorage.getItem(LAYOUT_KEY)]).toEqual(["circular", "circular"]);
  unmount();
  expect(renderHook(() => useLayout()).result.current.layout).toBe("circular");
});

it("falls back to Adaptive on a value it does not know", () => {
  localStorage.setItem(LAYOUT_KEY, "spiral");
  expect(renderHook(() => useLayout()).result.current.layout).toBe("adaptive");
});

it("works for the visit when storage refuses", () => {
  vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
    throw new Error("denied");
  });
  vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
    throw new Error("denied");
  });
  const { result } = renderHook(() => useLayout());
  act(() => result.current.pick("grid"));
  expect(result.current.layout).toBe("grid");
});
