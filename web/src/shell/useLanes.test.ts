import { act, renderHook } from "@testing-library/react";
import { LANES_KEY, readLanes, useLanes } from "./useLanes";

afterEach(() => {
  localStorage.clear();
  vi.restoreAllMocks();
});

it("starts wide, and remembers narrow in this browser", () => {
  const { result } = renderHook(() => useLanes());
  expect(result.current.lanes).toBe("wide");
  act(() => result.current.toggle());
  expect(result.current.lanes).toBe("narrow");
  expect(localStorage.getItem(LANES_KEY)).toBe("narrow");
  expect(renderHook(() => useLanes()).result.current.lanes).toBe("narrow");
  act(() => result.current.toggle());
  expect(localStorage.getItem(LANES_KEY)).toBe("wide");
});

it("reads anything but narrow as wide", () => {
  localStorage.setItem(LANES_KEY, "sideways");
  expect(readLanes()).toBe("wide");
});

// A private window, or site data blocked: storage throws, and the toggle still works for the visit.
it("keeps working when storage refuses", () => {
  vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
    throw new Error("denied");
  });
  vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
    throw new Error("denied");
  });
  const { result } = renderHook(() => useLanes());
  expect(result.current.lanes).toBe("wide");
  act(() => result.current.toggle());
  expect(result.current.lanes).toBe("narrow");
});
