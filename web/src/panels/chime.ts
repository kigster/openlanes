// A short two-note boop each time a question arrives in the rail, so a person working in another window hears that
// an agent is waiting. Off or on is the project's setting, `chime:` in .openlanes.yml, which the engine reports on
// every snapshot and the checkbox writes through a command, so it holds across reloads, browsers and restarts. A
// browser plays no sound on a page nobody has clicked yet, so the first boop after a reload may be silent.
// On a phone the boop comes back while a question is still waiting: a phone is in a pocket, and one boop that was
// missed was the only one there would ever be.
import { useCallback, useEffect, useRef, useState } from "react";
import { usePhone } from "../shell/usePhone";

/** The most boops one update plays: ten questions landing at once is one alarm, not ten. */
export const CHIME_LIMIT = 3;
/** Seconds between the boops of one update. */
const GAP = 0.28;
/** The two notes, in Hz: A5 then D6. */
const NOTES = [880, 1174.66];

/** The most dings one waiting spell plays on a phone, the one that opened it included. */
export const CHIME_DINGS = 10;
/** Seconds before the first and the second repeat; every gap after those is the sum of the two before it. */
const FIRST_GAPS = [10, 15] as const;

/**
 * The waits between the dings of one waiting spell, in seconds: `gaps[n - 1]` is how long after ding `n` the next one
 * plays. They grow like Fibonacci, 10, 15, 25, 40, 65…, so a question left for a minute is asked about four times and
 * one left for an hour is not asked about four hundred.
 *
 * @param dings how many dings the spell may play in all, the first included
 * @return one gap fewer than `dings`, since nothing follows the last
 */
export function chimeGaps(dings: number = CHIME_DINGS): number[] {
  const gaps: number[] = [];
  for (let i = 0; i < dings - 1; i += 1) gaps.push(i < FIRST_GAPS.length ? FIRST_GAPS[i] : gaps[i - 1] + gaps[i - 2]);
  return gaps;
}

const GAPS = chimeGaps();

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
 *
 * On a phone, while any id is still waiting and sound is on, it boops again after each of {@link chimeGaps}. Every
 * boop of the spell counts toward {@link CHIME_DINGS}, whatever caused it: the one for the question that opened the
 * spell is ding 1, and one for a question arriving mid-spell takes the next place and the next, longer gap, so a new
 * arrival never restarts the series at ten seconds. The spell ends when `ids` is empty, and the next question starts
 * a fresh one. A question that arrives after the tenth ding is still announced once; it is not repeated.
 */
export function useChime(ids: string[], saved: boolean, save: (on: boolean) => void, play: (count: number) => void = boop) {
  const [choice, setChoice] = useState<boolean | null>(null);
  useEffect(() => { setChoice(null); }, [saved]);
  const on = choice ?? saved;
  const phone = usePhone();
  const waiting = ids.length > 0;
  // How many times this spell has rung. Kept as state, not a ref: each ring has to schedule the one after it.
  const [dings, setDings] = useState(0);
  const ring = useCallback((count: number) => {
    play(count);
    setDings((n) => n + 1);
  }, [play]);
  const seen = useRef(new Set<string>());
  const key = ids.join("\n");
  useEffect(() => {
    const fresh = ids.filter((id) => !seen.current.has(id));
    fresh.forEach((id) => seen.current.add(id));
    if (on && fresh.length > 0) ring(Math.min(fresh.length, CHIME_LIMIT));
    // `key` stands for `ids`: a new array with the same ids is not a new question.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, on, ring]);
  // Nothing waiting: the spell is over, and so is its count. Also drops a ring made with nothing waiting (the
  // checkbox's own), which would otherwise be carried into the next spell as its first ding.
  useEffect(() => {
    if (!waiting && dings > 0) setDings(0);
  }, [waiting, dings]);
  // The repeat. One timer at a time, for the gap that follows the ding just played; turning sound off, the last
  // answer, or leaving phone size clears it, so nothing rings after the reason for it has gone.
  useEffect(() => {
    if (!phone || !on || !waiting) return;
    const gap = GAPS[dings - 1]; // none before the first ding, and none after the last
    if (gap === undefined) return;
    const timer = setTimeout(() => ring(1), gap * 1000);
    return () => clearTimeout(timer);
  }, [phone, on, waiting, dings, ring]);
  const toggle = useCallback((next: boolean) => {
    setChoice(next);
    save(next);
    if (next) ring(1); // the click is the gesture a browser wants, and says what the box does
  }, [ring, save]);
  return { on, toggle };
}
