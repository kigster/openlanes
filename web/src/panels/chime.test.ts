import { renderHook, act } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { boop, CHIME_LIMIT, useChime } from "./chime";

// jsdom has no Web Audio, so the sound itself is a fake that counts what was asked of it.
function fakeAudio() {
  const started: number[] = [];
  const hz: number[] = [];
  class FakeContext {
    currentTime = 10;
    destination = {};
    resume = vi.fn(() => Promise.resolve());
    createOscillator() {
      const frequency = { set value(v: number) { hz.push(v); } };
      return { type: "", frequency, connect: (node: unknown) => node, start: (at: number) => started.push(at), stop: vi.fn() };
    }
    createGain() {
      return { gain: { setValueAtTime: vi.fn(), exponentialRampToValueAtTime: vi.fn() }, connect: vi.fn() };
    }
  }
  return { FakeContext, started, hz };
}

describe("boop", () => {
  afterEach(() => { vi.unstubAllGlobals(); });

  it("does nothing where there is no Web Audio", () => {
    vi.stubGlobal("AudioContext", undefined);
    expect(() => boop(2)).not.toThrow();
  });

  it("plays two notes for each boop, one boop after another", () => {
    const { FakeContext, started, hz } = fakeAudio();
    vi.stubGlobal("AudioContext", FakeContext);
    boop(2);
    expect(hz).toEqual([880, 1174.66, 880, 1174.66]);
    expect(started).toHaveLength(4);
    expect(started[2]).toBeGreaterThan(started[1]);
  });

  it("stays quiet when the browser refuses audio", () => {
    vi.stubGlobal("AudioContext", class { resume() { throw new Error("not allowed"); } });
    expect(() => boop(1)).not.toThrow();
  });
});

describe("useChime", () => {
  const setup = (ids: string[], saved: boolean) => {
    const play = vi.fn();
    const save = vi.fn();
    const hook = renderHook(({ ids, saved }) => useChime(ids, saved, save, play), { initialProps: { ids, saved } });
    return { play, save, ...hook };
  };

  it("boops once for each new question, and never more than the limit", () => {
    const { play, rerender } = setup(["a"], true);
    expect(play.mock.calls).toEqual([[1]]);
    rerender({ ids: ["a"], saved: true });
    rerender({ ids: ["a", "b", "c", "d", "e", "f"], saved: true });
    expect(play.mock.calls).toEqual([[1], [CHIME_LIMIT]]);
  });

  it("remembers what arrived while it was off, so turning it on replays nothing", () => {
    const { play, rerender } = setup(["a", "b"], false);
    rerender({ ids: ["a", "b"], saved: true });
    expect(play).not.toHaveBeenCalled();
  });

  it("answers the click at once, saves it, and boops once when turned on", () => {
    const { play, save, result } = setup([], false);
    act(() => result.current.toggle(true));
    expect([result.current.on, save.mock.calls, play.mock.calls]).toEqual([true, [[true]], [[1]]]);
    act(() => result.current.toggle(false));
    expect([result.current.on, save.mock.calls.at(-1), play.mock.calls.length]).toEqual([false, [false], 1]);
  });

  it("goes back to what the engine reports once it reports again", () => {
    const { result, rerender } = setup([], true);
    act(() => result.current.toggle(false));
    rerender({ ids: [], saved: false });
    rerender({ ids: [], saved: true });
    expect(result.current.on).toBe(true);
  });
});
