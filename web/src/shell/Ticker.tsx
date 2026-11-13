// The strip beside the Board and Logs tabs: the last three lines of the log, so what the factory is doing right now
// is on screen without opening Logs. Debug lines are left out, as the Logs tab leaves them out until asked. The whole
// strip is one button that opens Logs, named by what it shows: a label that hid its visible text would fail a speech user
// who says what they see. It is not a live region, since the Logs tab already counts warnings.
import type { LogLine } from "../api/types";
import { stamp } from "../board/format";

/** How many lines the strip shows. */
export const TICKER_LINES = 3;

export function Ticker({ lines, onOpen }: { lines: LogLine[]; onOpen: () => void }) {
  const last = lines.filter(l => l.level !== "debug").slice(-TICKER_LINES);
  if (last.length === 0) return <span className="ticker is-empty" />;
  return (
    <button type="button" className="ticker" onClick={onOpen} title="What is happening now. Click for the full log">
      <span className="sr-only">Open Logs. Latest activity: </span>
      {last.map((line, i) => (
        <span key={`${line.at}-${i}`} className={`ticker-line is-${line.level}`}>
          <span className="ticker-at">{stamp(line.at)}</span>
          <span className="ticker-src">{line.plan ? `${line.plan} ${line.source}` : line.source}</span>
          <span className="ticker-text">{line.text}</span>
        </span>
      ))}
    </button>
  );
}
