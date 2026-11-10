// The refactor global lock (R6): one band across the top of the page while a `global-lock-required` refactor runs
// alone, counting down to when its lock lapses and other plans may start beside it again. Red once it has lapsed.
import { useEffect, useId, useState } from "react";
import type { GlobalLock } from "../api/types";
import { countdown } from "./countdown";

export interface GlobalLockBannerProps {
  /** `snapshot.global_lock` of this machine: null draws nothing. */
  lock: GlobalLock | null;
  /** Clock override in epoch ms, for tests; the banner ticks its own every second. */
  now?: number;
}

/** Epoch ms, refreshed every second while `on`, so the countdown moves between snapshots. */
function useSeconds(on: boolean, override?: number): number {
  const [tick, setTick] = useState(() => Date.now());
  useEffect(() => {
    if (!on || override !== undefined) return;
    const id = setInterval(() => setTick(Date.now()), 1000);
    return () => clearInterval(id);
  }, [on, override]);
  return override ?? tick;
}

const when = (iso: string): string =>
  new Date(iso).toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

const hours = (seconds: number): string => `${Math.round((seconds / 3600) * 10) / 10} h`;

export function GlobalLockBanner({ lock, now }: GlobalLockBannerProps) {
  const id = useId();
  const clock = useSeconds(lock !== null && !lock.expired, now);
  if (lock === null) return null;

  const left = lock.expires_at === null ? null : new Date(lock.expires_at).getTime() - clock;
  const lapsed = lock.expired || (left !== null && left <= 0);
  const note = lapsed
    ? "Other plans start beside it again."
    : lock.waits_on.length > 0
      ? `Nothing new starts. Its build waits on ${lock.waits_on.join(", ")} to merge or close.`
      : "Nothing new starts until it merges.";

  return (
    <section className="global-lock" aria-labelledby={`${id}-title`} data-plan={lock.plan} data-expired={lapsed}>
      <h2 id={`${id}-title`} className="global-lock-title">
        <span aria-hidden="true">🔒 </span>
        {lapsed ? "Global lock lapsed" : "Global lock"}: refactor {lock.plan} {lock.title}
      </h2>
      <p className="global-lock-note">{note}</p>
      {lapsed ? (
        <p className="global-lock-timer">{lock.expires_at === null ? "lapsed" : `lapsed ${when(lock.expires_at)}`}</p>
      ) : left === null ? (
        <p className="global-lock-timer">lapses {hours(lock.ttl)} after it is taken</p>
      ) : (
        <p className="global-lock-timer">
          lapses in{" "}
          <time role="timer" dateTime={lock.expires_at!}>
            {countdown(left)}
          </time>
        </p>
      )}
    </section>
  );
}
