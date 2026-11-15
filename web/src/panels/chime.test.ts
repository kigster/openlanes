import { renderHook, act } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { boop, CHIME_DINGS, CHIME_LIMIT, chimeGaps, useChime } from "./chime";
import { PHONE_QUERY } from "../shell/usePhone";
import { stubMedia } from "../test/media";

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

describe("chimeGaps", () => {
  it("waits 10 s, then 15, then the sum of the two waits before, for ten dings in all", () => {
    expect([CHIME_DINGS, chimeGaps()]).toEqual([10, [10, 15, 25, 40, 65, 105, 170, 275, 445]]);
  });

  it("has one gap fewer than dings, and none for a single ding or for none", () => {
    expect([chimeGaps(4), chimeGaps(2), chimeGaps(1), chimeGaps(0)]).toEqual([[10, 15, 25], [10], [], []]);
  });
});

describe("the repeat on a phone", () => {
  const setup = (ids: string[], saved = true) => {
    const play = vi.fn();
    const save = vi.fn();
    const hook = renderHook(({ ids, saved }) => useChime(ids, saved, save, play), { initialProps: { ids, saved } });
    return { play, ...hook };
  };
  const pass = (seconds: number) => act(() => { vi.advanceTimersByTime(seconds * 1000); });
  const phone = () => stubMedia((query) => query === PHONE_QUERY);

  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("rings again after 10 s, 15 s and 25 s, and not a moment before each", () => {
    phone();
    const { play } = setup(["a"]);
    const counts = [play.mock.calls.length];
    for (const seconds of [9.9, 0.1, 14.9, 0.1, 24.9, 0.1]) {
      pass(seconds);
      counts.push(play.mock.calls.length);
    }
    expect(counts).toEqual([1, 1, 2, 2, 3, 3, 4]);
    expect(play.mock.calls.slice(1)).toEqual([[1], [1], [1]]); // a repeat is one boop, however many are waiting
  });

  // The first chime is ding 1, so nine repeats follow it: 1150 s of gaps in all, and silence after.
  it("stops at ten dings, the first chime counted, however long the question waits", () => {
    phone();
    const { play } = setup(["a"]);
    // One wait at a time: each ding schedules the next only once React has rendered it.
    chimeGaps().forEach(pass);
    const atTheLast = play.mock.calls.length;
    pass(24 * 3600);
    expect([atTheLast, play.mock.calls.length]).toEqual([CHIME_DINGS, CHIME_DINGS]);
  });

  it("stops the moment nothing is waiting, and starts a fresh series for the next question", () => {
    phone();
    const { play, rerender } = setup(["a"]);
    pass(10);
    pass(15);
    rerender({ ids: [], saved: true });
    pass(3600);
    const afterAnswer = play.mock.calls.length;
    rerender({ ids: ["b"], saved: true });
    const arrived = play.mock.calls.length;
    pass(9.9);
    const early = play.mock.calls.length;
    pass(0.1);
    expect([afterAnswer, arrived, early, play.mock.calls.length]).toEqual([3, 4, 4, 5]);
  });

  it("counts a question arriving mid-spell as the next ding: the series goes on, it does not start over", () => {
    phone();
    const { play, rerender } = setup(["a"]);
    pass(5);
    rerender({ ids: ["a", "b"], saved: true }); // ding 2, five seconds in: the next wait is the second gap, 15 s
    const arrived = play.mock.calls.length;
    pass(14.9);
    const early = play.mock.calls.length;
    pass(0.1);
    expect([arrived, early, play.mock.calls.length]).toEqual([2, 2, 3]);
  });

  it("never repeats on a wide page", () => {
    const { play } = setup(["a"]);
    pass(3600);
    expect(play.mock.calls).toEqual([[1]]);
  });

  it("stays quiet while sound is off, and takes up the series once it is turned on", () => {
    phone();
    const { play, result } = setup(["a"], false);
    pass(3600);
    const whileOff = play.mock.calls.length;
    act(() => result.current.toggle(true)); // the checkbox's own boop is this spell's first ding
    pass(10);
    const on = play.mock.calls.length;
    act(() => result.current.toggle(false));
    pass(3600);
    expect([whileOff, on, play.mock.calls.length]).toEqual([0, 2, 2]);
  });

  it("does not carry the checkbox's boop, made with nothing waiting, into the next spell", () => {
    phone();
    const { play, result, rerender } = setup([], false);
    act(() => result.current.toggle(true));
    pass(3600);
    const idle = play.mock.calls.length;
    rerender({ ids: ["a"], saved: false });
    pass(9.9);
    const early = play.mock.calls.length;
    pass(0.1);
    expect([idle, early, play.mock.calls.length]).toEqual([1, 2, 3]);
  });

  it("clears its timer when the rail goes away", () => {
    phone();
    const { play, unmount } = setup(["a"]);
    unmount();
    pass(3600);
    expect(play.mock.calls).toEqual([[1]]);
  });
});
