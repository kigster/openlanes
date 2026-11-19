import { act, renderHook } from "@testing-library/react";
import { LAYOUT_KEY, useLayout } from "./useLayout";

beforeEach(() => localStorage.clear());
afterEach(() => vi.restoreAllMocks());

it("starts on Circular, and keeps a pick for the next visit", () => {
  const { result, unmount } = renderHook(() => useLayout());
  expect(result.current.layout).toBe("circular");
  act(() => result.current.pick("adaptive"));
  expect([result.current.layout, localStorage.getItem(LAYOUT_KEY)]).toEqual(["adaptive", "adaptive"]);
  unmount();
  expect(renderHook(() => useLayout()).result.current.layout).toBe("adaptive");
});

it("falls back to Circular on a value it does not know", () => {
  localStorage.setItem(LAYOUT_KEY, "spiral");
  expect(renderHook(() => useLayout()).result.current.layout).toBe("circular");
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
