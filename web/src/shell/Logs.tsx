import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { LogLine } from "../api/types";
import { stamp } from "../board/format";

const LEVELS: LogLine["level"][] = ["debug", "info", "warn", "error"];
/** The sources the mockup offers before any line arrives; others (redis, an agent's name) join as they appear. */
const BASE_SOURCES = ["engine", "api"];

const toggleIn = <T,>(set: ReadonlySet<T>, item: T): Set<T> => {
  const next = new Set(set);
  if (next.has(item)) next.delete(item);
  else next.add(item);
  return next;
};

/**
 * The Logs tab: the snapshot's tail of engine.log and api.log, with filters for source and level, a text filter, and
 * Follow, which turns itself off when you scroll up and back on at the bottom.
 */
export function Logs({ lines }: { lines: LogLine[] }) {
  // Hidden rather than shown, so a source that appears later is on until someone turns it off.
  const [hiddenSources, setHiddenSources] = useState<ReadonlySet<string>>(new Set());
  const [hiddenLevels, setHiddenLevels] = useState<ReadonlySet<string>>(new Set(["debug"]));
  const [text, setText] = useState("");
  const [following, setFollowing] = useState(true);
  const list = useRef<HTMLOListElement>(null);

  const sources = useMemo(() => [...new Set([...BASE_SOURCES, ...lines.map(l => l.source)])], [lines]);
  const needle = text.trim().toLowerCase();
  const shown = lines.filter(
    l => !hiddenSources.has(l.source) && !hiddenLevels.has(l.level) && (!needle || l.text.toLowerCase().includes(needle)),
  );

  useLayoutEffect(() => {
    const el = list.current;
    if (following && el) el.scrollTop = el.scrollHeight;
  });

  // Scrolling up to read stops following; scrolling back to the bottom resumes it.
  useEffect(() => {
    const el = list.current;
    if (!el) return;
    const onScroll = () => setFollowing(el.scrollHeight - el.scrollTop - el.clientHeight < 24);
    el.addEventListener("scroll", onScroll);
    return () => el.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <>
      <div className="log-tools">
        <fieldset>
          <legend>Show</legend>
          {sources.map(src => (
            <button key={src} className="toggle" type="button" aria-pressed={!hiddenSources.has(src)} onClick={() => setHiddenSources(s => toggleIn(s, src))}>
              {src}
            </button>
          ))}
        </fieldset>
        <fieldset>
          <legend>Level</legend>
          {LEVELS.map(lvl => (
            <button key={lvl} className="toggle" type="button" aria-pressed={!hiddenLevels.has(lvl)} onClick={() => setHiddenLevels(s => toggleIn(s, lvl))}>
              {lvl}
            </button>
          ))}
        </fieldset>
        <label className="sr-only" htmlFor="log-search">
          Filter log lines
        </label>
        <input
          className="log-search"
          id="log-search"
          type="search"
          placeholder="Filter, e.g. 001 or an agent's name"
          value={text}
          onChange={e => setText(e.target.value)}
        />
        <button className="toggle log-follow" type="button" aria-pressed={following} onClick={() => setFollowing(f => !f)}>
          Follow
        </button>
      </div>
      <ol className="log" ref={list} aria-label="Log lines, newest last" tabIndex={0}>
        {shown.length ? (
          shown.map((line, i) => (
            <li key={`${line.at}-${i}`} className={`is-${line.level}`}>
              <time dateTime={line.at}>{stamp(line.at)}</time>
              <span className="lvl">{line.level}</span>
              <span className="src">{line.source}</span>
              <span className="msg">{line.text}</span>
            </li>
          ))
        ) : (
          <li className="log-empty">No lines match. Loosen the filters above.</li>
        )}
      </ol>
      <p className="log-path">Tailing .openlanes/log/engine.log and .openlanes/log/api.log</p>
    </>
  );
}
