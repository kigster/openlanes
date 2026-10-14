import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";
import { flushSync } from "react-dom";
import * as Tabs from "@radix-ui/react-tabs";
import { MotionConfig, useReducedMotion } from "motion/react";
import type { Board as BoardData, Car, Plan } from "./api/types";
import { useBoard, type ConnectionState } from "./api/useBoard";
import { useSendCommand } from "./api/useSendCommand";
import { Board, MachineBoard } from "./board/Board";
import { ChatRoom, MachineMenu } from "./chat";
import { Copilot } from "./copilot/Copilot";
import { planId, who } from "./board/format";
import { isWorking, nodePlanKey, rowDomId, testRuns, testTabLabel, testTabValue } from "./board/model";
import { useLifecycle } from "./board/useLifecycle";
import { Header } from "./shell/Header";
import { Logs } from "./shell/Logs";
import { StatusBar } from "./shell/StatusBar";
import { TestsPanel } from "./shell/TestsPanel";
import { backlogNote } from "./shell/notes";
import { useBoardNews } from "./shell/useBoardNews";
import {
  ActionMenu,
  AgentDrawer,
  AnnouncerProvider,
  HelpDialog,
  ModelSelect,
  NeedsYou,
  StopAllDialog,
  UnblockWidget,
  type SendCommand,
  useAnnounce,
} from "./panels";
import "./shell/shell.css";

const MERGED_KEY = "openlanes-merged";
const machineTab = (nodeId: string) => `node:${nodeId}`;

function readMerged(): boolean {
  try {
    return localStorage.getItem(MERGED_KEY) === "1";
  } catch {
    return false; // a private window: start with this machine only
  }
}

function writeMerged(on: boolean): void {
  try {
    localStorage.setItem(MERGED_KEY, on ? "1" : "0");
  } catch {
    // a private window: the toggle lasts for this visit only
  }
}

interface OpenCar {
  plan: string;
  agent: string;
}

const STEPS: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1 };

/**
 * The tabs sit in several tablists (each machine's in its own, beside its ▾), each a roving-focus group of its own.
 * Taken before any group sees them, the arrows, Home and End move across every tab in the row, as in one list, and
 * switch to the tab they land on. Focus alone does not switch (activationMode manual): with it automatic, pressing Tab
 * to walk past the row focused the first machine's tab, which selected it and swapped the Board out from under the
 * person, who then could never Tab to a car.
 */
function acrossTabs(e: KeyboardEvent<HTMLElement>, activate: (tab: HTMLElement) => void): void {
  const from = e.target;
  const step = STEPS[e.key];
  const edge = e.key === "Home" || e.key === "End";
  if ((!step && !edge) || !(from instanceof HTMLElement) || from.getAttribute("role") !== "tab") return;
  const tabs = Array.from(e.currentTarget.querySelectorAll<HTMLElement>('[role="tab"]'));
  const at = tabs.indexOf(from);
  const to = edge ? (e.key === "Home" ? 0 : tabs.length - 1) : (at + step + tabs.length) % tabs.length;
  e.preventDefault(); // the group's own handler stands down for a prevented event
  const target = tabs[to];
  target?.focus();
  if (target) activate(target);
}

function ControlRoom({ board, connection, fixture }: { board: BoardData; connection: ConnectionState; fixture: boolean }) {
  const { me, others } = board;
  const { announce } = useAnnounce();
  const reduced = useReducedMotion() ?? false;
  const send = useSendCommand();
  const onCommand = useCallback<SendCommand>(command => send.mutateAsync(command), [send]);
  const life = useLifecycle(me.plans, reduced);
  // Other machines' merged rows stay and fade like ours; one hook tracks them all, keyed by machine and plan.
  const theirPlans = useMemo(
    () => others.flatMap(o => o.plans.map(p => ({ ...p, ordinal: nodePlanKey(o.node.id, p.ordinal) }))),
    [others],
  );
  const theirLife = useLifecycle(theirPlans, reduced);
  useBoardNews(me, announce);

  const [tab, setTab] = useState("board");
  const [merged, setMergedState] = useState(readMerged);
  const [openCar, setOpenCar] = useState<OpenCar | null>(null);
  const [unblocking, setUnblocking] = useState<string | null>(null);
  const [logsSeenAt, setLogsSeenAt] = useState<string | null>(null);
  // #start in the URL opens the idea dialog, so `openlanes start` can send the browser straight to it (W19).
  const [ideaOpen, setIdeaOpen] = useState(() => window.location.hash === "#start");
  const pressedSelected = useRef(false);
  // The hash is spent on the first load: left in the address bar, every refresh reopened the dialog over a board
  // that by then had its plan. Stripped in an effect, not the initializer, which StrictMode runs twice.
  useEffect(() => {
    if (window.location.hash !== "#start") return;
    const { pathname, search } = window.location;
    window.history.replaceState(window.history.state, "", pathname + search);
  }, []);
  // The machine whose chat menu is open (D3): its ▾, or a right-click on its tab.
  const [menuFor, setMenuFor] = useState<string | null>(null);

  const runs = useMemo(() => testRuns(me.plans), [me.plans]);
  const tabs = ["board", "logs", ...runs.map(testTabValue), ...others.map(o => machineTab(o.node.id))];
  // A tab whose run finished or whose machine left falls back to the Board.
  const current = tabs.includes(tab) ? tab : "board";

  const newest = me.log.at(-1)?.at ?? null;
  useEffect(() => {
    if (current === "logs" || logsSeenAt === null) setLogsSeenAt(newest ?? "");
  }, [current, newest, logsSeenAt]);
  const alerts = logsSeenAt === null ? 0 : me.log.filter(l => (l.level === "warn" || l.level === "error") && l.at > logsSeenAt).length;

  const setMerged = useCallback(
    (on: boolean) => {
      setMergedState(on);
      writeMerged(on);
      if (on) setTab("board");
      announce(on ? "Showing every machine's plans. Theirs are below ours, read only." : "Showing this machine's plans only.");
    },
    [announce],
  );

  const drawer = openCar && me.plans.find(p => p.ordinal === openCar.plan);
  const drawerCar = drawer ? drawer.cars.find(c => c.agent === openCar?.agent) : undefined;
  const unblockPlan = unblocking ? (me.plans.find(p => p.ordinal === unblocking) ?? null) : null;

  const onOpenCar = useCallback((plan: Plan, car: Car) => setOpenCar({ plan: plan.ordinal, agent: car.agent }), []);
  const closeDrawer = useCallback(() => {
    const was = openCar;
    setOpenCar(null);
    if (was) document.querySelector<HTMLElement>(`[data-car="${was.plan}/${was.agent}"] .car-open`)?.focus();
  }, [openCar]);

  const onToggleUnblock = useCallback(
    (plan: Plan) => {
      if (unblocking === plan.ordinal) {
        setUnblocking(null);
        return;
      }
      setUnblocking(plan.ordinal);
      const ask = plan.questions[0];
      const why = ask ? ask.body || ask.heading : `you interrupted ${plan.interrupted?.agent ?? "its agent"}`;
      announce(`${planId(plan.ordinal)} needs you: ${why}`);
    },
    [unblocking, announce],
  );
  const closeUnblock = useCallback(() => {
    const was = unblocking;
    setUnblocking(null);
    if (was) document.querySelector<HTMLElement>(`.pill[data-plan="${was}"]`)?.focus();
  }, [unblocking]);

  // Any pill but a red one with a request: switch to the Board and bring the plan's row into view. A blocked agent
  // with no request opens its drawer instead.
  const onShowPlan = useCallback(
    (plan: Plan) => {
      flushSync(() => setTab("board"));
      const row = document.getElementById(rowDomId(plan.ordinal));
      row?.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
      const stuck = plan.cars.find(c => c.state === "stuck" || c.state === "failed");
      if (stuck) {
        onOpenCar(plan, stuck);
        return;
      }
      row?.querySelector<HTMLElement>(".car-open, .pr-link")?.focus({ preventScroll: true });
    },
    [reduced, onOpenCar],
  );

  const renderModel = useCallback(
    (plan: Plan, car: Car) => <ModelSelect plan={plan.ordinal} car={car} models={me.models} mode="next" onCommand={onCommand} />,
    [me.models, onCommand],
  );

  // Stop All Local counts agents that are still at it: a done or failed car lingers on the board but has nothing to stop.
  const busy = me.plans.map(p => p.cars.filter(isWorking).length).filter(n => n > 0);

  return (
    <ChatRoom user={me.node.user} enabled={!fixture}>
      <Header
        snapshot={me}
        connection={connection}
        fixture={fixture}
        merged={merged}
        onToggleMerged={() => setMerged(!merged)}
        actionMenu={<ActionMenu backlog={me.backlog} onCommand={onCommand} note={backlogNote(board)} ideaOpen={ideaOpen} onIdeaOpenChange={setIdeaOpen} />}
        stopAll={<StopAllDialog agents={busy.reduce((sum, n) => sum + n, 0)} plans={busy.length} onCommand={onCommand} />}
        help={<HelpDialog />}
      />
      <Tabs.Root className="tabs-root" value={current} onValueChange={setTab} activationMode="manual">
        {/* A tablist may hold tabs only, so each machine's tab sits in a tablist of its own with its ▾ beside it (D3);
            the arrow keys still walk every tab as one row. */}
        <div className="tabs" onKeyDownCapture={e => acrossTabs(e, tab => tab.dataset.tab && setTab(tab.dataset.tab))}>
          <Tabs.List className="tabs-list" aria-label="Views">
            <Tabs.Trigger className="tab" value="board" data-tab="board">
              Board
            </Tabs.Trigger>
            <Tabs.Trigger className="tab" value="logs" data-tab="logs">
              Logs
              <span className="tab-count" title="Warnings and errors since you last looked">
                {alerts || ""}
              </span>
            </Tabs.Trigger>
            {runs.map(run => (
              <Tabs.Trigger key={testTabValue(run)} className="tab" value={testTabValue(run)} data-tab={testTabValue(run)} title={`${run.car.agent} ran ${run.cmd}`}>
                {testTabLabel(run, runs)}
                <span className="run-chip">
                  {run.done} of {run.total}
                </span>
              </Tabs.Trigger>
            ))}
          </Tabs.List>
            {others.map(o => {
              const value = machineTab(o.node.id);
              // A machine tab toggles: the first press shows just that machine, the second shows all of them on the Board.
              const note = () => {
                pressedSelected.current = current === value;
              };
              return (
                <span key={value} className="tab-machine-wrap">
                  <Tabs.List className="tabs-list" aria-label={`Machine ${who(o.node)}`}>
                    <Tabs.Trigger
                      className="tab tab-machine"
                      value={value}
                      data-tab={value}
                      title={`Read only: what ${who(o.node)} is working on. Press again to see every machine. Right-click to chat.`}
                      onPointerDown={note}
                      onKeyDown={e => (e.key === "Enter" || e.key === " ") && note()}
                      onClick={() => {
                        if (pressedSelected.current) setMerged(true);
                        pressedSelected.current = false;
                      }}
                      onContextMenu={e => {
                        if (fixture) return;
                        e.preventDefault();
                        setMenuFor(o.node.id);
                      }}
                    >
                      {who(o.node)}
                    </Tabs.Trigger>
                  </Tabs.List>
                  <MachineMenu node={o.node} open={menuFor === o.node.id} onOpenChange={open => setMenuFor(open ? o.node.id : null)} />
                </span>
              );
            })}
        </div>
        <UnblockWidget plan={unblockPlan} onCommand={onCommand} onClose={closeUnblock} />
        <main className="layout">
          <Tabs.Content value="board" className="board" forceMount hidden={current !== "board"}>
            <Board
              board={board}
              merged={merged}
              retiring={life.retiring}
              gone={life.gone}
              theirs={theirLife}
              openCar={drawer && drawerCar ? drawerCar.key : null}
              onOpenCar={onOpenCar}
              renderModel={renderModel}
            />
          </Tabs.Content>
          {others.map(o => (
            <Tabs.Content key={o.node.id} value={machineTab(o.node.id)} className="board">
              <MachineBoard their={o} me={me} life={theirLife} />
            </Tabs.Content>
          ))}
          <Tabs.Content value="logs" className="logs" forceMount hidden={current !== "logs"}>
            <Logs lines={me.log} />
          </Tabs.Content>
          {runs.map(run => (
            <Tabs.Content key={testTabValue(run)} value={testTabValue(run)} className="tests">
              <TestsPanel run={run} />
            </Tabs.Content>
          ))}
          {drawer && drawerCar ? (
            <AgentDrawer plan={drawer} car={drawerCar} models={me.models} autocompact={me.autocompact} onCommand={onCommand} onClose={closeDrawer} />
          ) : (
            <NeedsYou plans={me.plans} onCommand={onCommand} />
          )}
        </main>
      </Tabs.Root>
      <StatusBar
        plans={me.plans}
        stations={me.stations}
        others={others}
        gone={life.gone}
        offBar={life.offBar}
        finishOrder={life.finishOrder}
        unblocking={unblocking}
        onToggleUnblock={onToggleUnblock}
        onShowPlan={onShowPlan}
        onOpenMachine={id => setTab(machineTab(id))}
        onDropGone={life.dropFromBar}
      />
      <Copilot onCommand={onCommand} models={me.models} />
    </ChatRoom>
  );
}

/** The control room. Needs a QueryClientProvider above it (main.tsx). */
export default function App() {
  const { board, waiting, error, connection, fixture } = useBoard();
  return (
    <MotionConfig reducedMotion="user">
      <AnnouncerProvider>
        {board ? (
          <ControlRoom board={board} connection={connection} fixture={fixture} />
        ) : error ? (
          <main className="loading is-error" role="alert">
            Could not load the board: {error.message}. Is openlanes start (or openlanes run) running?
          </main>
        ) : (
          // The server answered with no engine on the board yet (`openlanes web` on its own): the stream brings the first
          // snapshot, and the page draws itself then. Until it does, a bare "waiting" read as a broken page, so it says
          // what would start one.
          <main className="loading" aria-busy="true">
            {waiting ? (
              <>
                <p>No engine is running for this checkout, so there is no board to show yet.</p>
                <p>
                  Please use <code>openlanes start</code>, or start an engine in another terminal by running{" "}
                  &quot;<code>openlanes run</code>&quot;.
                </p>
              </>
            ) : (
              "Connecting to the engine…"
            )}
          </main>
        )}
      </AnnouncerProvider>
    </MotionConfig>
  );
}
