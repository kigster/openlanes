// A short two-note boop each time a question arrives in the rail, so a person working in another window hears that
// an agent is waiting. Off or on is the project's setting, `chime:` in .openlanes.yml, which the engine reports on
// every snapshot and the checkbox writes through a command, so it holds across reloads, browsers and restarts. A
// browser plays no sound on a page nobody has clicked yet, so the first boop after a reload may be silent.
import { useCallback, useEffect, useRef, useState } from "react";

/** The most boops one update plays: ten questions landing at once is one alarm, not ten. */
export const CHIME_LIMIT = 3;
/** Seconds between the boops of one update. */
const GAP = 0.28;
/** The two notes, in Hz: A5 then D6. */
const NOTES = [880, 1174.66];

let context: AudioContext | null = null;

/** Plays `count` boops, one after another. Does nothing where there is no Web Audio (jsdom, an old browser). */
export function boop(count: number): void {
  const Audio = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Audio) return;
  try {
    context ??= new Audio();
    const ctx = context;
    void ctx.resume();
    for (let i = 0; i < count; i += 1) {
      NOTES.forEach((hz, n) => {
        const at = ctx.currentTime + i * GAP + n * 0.09;
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = "sine";
        osc.frequency.value = hz;
        gain.gain.setValueAtTime(0.0001, at);
        gain.gain.exponentialRampToValueAtTime(0.18, at + 0.01);
        gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.16);
        osc.connect(gain).connect(ctx.destination);
        osc.start(at);
        osc.stop(at + 0.18);
      });
    }
  } catch {
    // a browser that refuses audio: the rail still shows the question
  }
}

/**
 * Boops once for each id in `ids` not seen before, up to {@link CHIME_LIMIT}, while sound is on.
 * Ids seen while sound was off are still remembered, so turning it on does not replay what is already on the page.
 *
 * `saved` is what the engine last reported; `save` sends the new choice to it. The box answers the click at once and
 * holds that until the engine's next report agrees or says otherwise, so it never flickers back between the two.
 */
export function useChime(ids: string[], saved: boolean, save: (on: boolean) => void, play: (count: number) => void = boop) {
  const [choice, setChoice] = useState<boolean | null>(null);
  useEffect(() => { setChoice(null); }, [saved]);
  const on = choice ?? saved;
  const seen = useRef(new Set<string>());
  const key = ids.join("\n");
  useEffect(() => {
    const fresh = ids.filter((id) => !seen.current.has(id));
    fresh.forEach((id) => seen.current.add(id));
    if (on && fresh.length > 0) play(Math.min(fresh.length, CHIME_LIMIT));
    // `key` stands for `ids`: a new array with the same ids is not a new question.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, on, play]);
  const toggle = useCallback((next: boolean) => {
    setChoice(next);
    save(next);
    if (next) play(1); // the click is the gesture a browser wants, and says what the box does
  }, [play, save]);
  return { on, toggle };
}
