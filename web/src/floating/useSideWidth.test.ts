import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, renderHook } from "@testing-library/react";
import { useSideWidth, SIDE_WIDTH_KEY, MIN_SIDE } from "./useSideWidth";

const layout = (clientWidth: number) => ({ current: { clientWidth } as HTMLElement });

describe("useSideWidth", () => {
  beforeEach(() => localStorage.clear());
  afterEach(() => vi.restoreAllMocks());

  it("defaults to 360 with nothing stored", () => {
    const { result } = renderHook(() => useSideWidth(layout(1400)));
    expect(result.current.width).toBe(MIN_SIDE);
    expect(result.current.max).toBe(840);
  });

  it("defaults to the layout's old clamp(360px, 30vw, 432px)", () => {
    const widthAt = (w: number) => {
      vi.stubGlobal("innerWidth", w);
      return renderHook(() => useSideWidth(layout(1400))).result.current.width;
    };
    expect([widthAt(1600), widthAt(1400), widthAt(1100)]).toEqual([432, 420, 360]);
    vi.unstubAllGlobals();
  });

  it("resets to that default, not to 360", () => {
    vi.stubGlobal("innerWidth", 1600);
    const { result } = renderHook(() => useSideWidth(layout(1600)));
    act(() => result.current.nudge(24));
    expect(result.current.width).toBe(456);
    act(() => result.current.reset());
    expect(result.current.width).toBe(432);
    vi.unstubAllGlobals();
  });

  it("restores a stored width on remount", () => {
    const first = renderHook(() => useSideWidth(layout(1400)));
    act(() => first.result.current.setWidth(500));
    first.unmount();
    const { result } = renderHook(() => useSideWidth(layout(1400)));
    expect(result.current.width).toBe(500);
    expect(localStorage.getItem(SIDE_WIDTH_KEY)).toBe("500");
  });

  it("survives a localStorage that throws on get and set", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("denied");
    });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("denied");
    });
    const { result } = renderHook(() => useSideWidth(layout(1400)));
    expect(result.current.width).toBe(MIN_SIDE);
    act(() => result.current.setWidth(450));
    expect(result.current.width).toBe(450);
  });

  it("clamps below 360 and above 60% of the layout", () => {
    const { result } = renderHook(() => useSideWidth(layout(1000)));
    act(() => result.current.setWidth(100));
    expect(result.current.width).toBe(360);
    act(() => result.current.setWidth(5000));
    expect(result.current.width).toBe(600);
  });

  it("re-clamps a stored width that is too wide for this layout", () => {
    localStorage.setItem(SIDE_WIDTH_KEY, "900");
    const { result } = renderHook(() => useSideWidth(layout(1000)));
    expect(result.current.width).toBe(600);
  });

  it("ignores an unparseable stored value", () => {
    localStorage.setItem(SIDE_WIDTH_KEY, "wide");
    const { result } = renderHook(() => useSideWidth(layout(1400)));
    expect(result.current.width).toBe(360);
  });

  it("nudges and resets, persisting each", () => {
    const { result } = renderHook(() => useSideWidth(layout(1400)));
    act(() => result.current.nudge(24));
    expect(result.current.width).toBe(384);
    act(() => result.current.reset());
    expect(result.current.width).toBe(360);
    expect(localStorage.getItem(SIDE_WIDTH_KEY)).toBeNull();
  });

  it("follows the media query", () => {
    let listener: () => void = () => {};
    let on = true;
    vi.spyOn(window, "matchMedia").mockImplementation(
      () => ({ get matches() { return on; }, addEventListener: (_: string, l: () => void) => (listener = l), removeEventListener() {} }) as unknown as MediaQueryList,
    );
    const { result } = renderHook(() => useSideWidth(layout(1400)));
    expect(result.current.wide).toBe(true);
    on = false;
    act(() => listener());
    expect(result.current.wide).toBe(false);
  });

  it("measures the maximum again on window resize", () => {
    const ref = layout(1000);
    const { result } = renderHook(() => useSideWidth(ref));
    expect(result.current.max).toBe(600);
    (ref.current as { clientWidth: number }).clientWidth = 2000;
    act(() => window.dispatchEvent(new Event("resize")));
    expect(result.current.max).toBe(1200);
  });
});
