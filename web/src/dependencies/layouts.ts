// The ways the Plan dependencies page can arrange its boxes. Pure: plans and links in, a top-left corner per plan
// out. The arrangement is a matter of view only, so nothing here reads or changes which plans and arrows are shown.
import dagre from "@dagrejs/dagre";
import type { DependencyPlan } from "../api/types";

export const NODE_WIDTH = 248;
export const NODE_HEIGHT = 72;

/** Room left between boxes that no arrow runs through. */
const GAP_X = 40;
const GAP_Y = 28;

/** The arrangements, in the order the picker offers them. */
export const LAYOUTS = [
  { key: "adaptive", name: "Adaptive", hint: "Chains run left to right and fold onto a new row when they get long; plans with no dependencies are packed in rows below" },
  { key: "right", name: "Left to right", hint: "Every plan in one layered graph, each dependency to the left of what needs it" },
  { key: "down", name: "Top to bottom", hint: "Every plan in one layered graph, each dependency above what needs it" },
  { key: "circular", name: "Circular", hint: "Plans around a ring, each chain's plans side by side" },
  { key: "grid", name: "Grid", hint: "Plans in rows, in plan number order" },
] as const;

export type LayoutKey = (typeof LAYOUTS)[number]["key"];

/** The arrangement a new browser starts on, or one whose kept pick is unreadable or unknown. */
export const DEFAULT_LAYOUT: LayoutKey = "circular";

/** Where arrows meet a box: its left and right edges, its top and bottom, or wherever the straight line crosses. */
export type Flow = "right" | "down" | "free";

export const flowOf = (kind: LayoutKey): Flow => (kind === "down" ? "down" : kind === "circular" || kind === "grid" ? "free" : "right");

export const isLayout = (value: unknown): value is LayoutKey => LAYOUTS.some(l => l.key === value);

export interface Point {
  x: number;
  y: number;
}

type Link = { from: string; to: string };
type Corners = Map<string, Point>;

/** How far apart dagre sets two ranks of a left-to-right graph, and how far apart two folded rows of one sit. */
const RANK_GAP = 90;
const FOLD_GAP = 56;

/** A layered graph through dagre, in the direction given. */
function layered(plans: DependencyPlan[], links: Link[], rankdir: "LR" | "TB"): Corners {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir, nodesep: GAP_Y, ranksep: rankdir === "LR" ? RANK_GAP : 64 });
  g.setDefaultEdgeLabel(() => ({}));
  for (const p of plans) g.setNode(p.ordinal, { width: NODE_WIDTH, height: NODE_HEIGHT });
  for (const l of links) if (g.hasNode(l.from) && g.hasNode(l.to)) g.setEdge(l.from, l.to);
  dagre.layout(g);
  return new Map(plans.map(p => [p.ordinal, { x: g.node(p.ordinal).x - NODE_WIDTH / 2, y: g.node(p.ordinal).y - NODE_HEIGHT / 2 }]));
}

/** Rows of `columns` boxes, filled in the order given, starting at `top`. */
function rows(plans: DependencyPlan[], columns: number, top = 0): Corners {
  return new Map(
    plans.map((p, i) => [p.ordinal, { x: (i % columns) * (NODE_WIDTH + GAP_X), y: top + Math.floor(i / columns) * (NODE_HEIGHT + GAP_Y) }]),
  );
}

/** As many columns as make the block about as wide as a screen is: roughly 16 by 10 in pixels. */
const columnsFor = (count: number) => Math.max(1, Math.ceil(Math.sqrt((count * 1.6 * (NODE_HEIGHT + GAP_Y)) / (NODE_WIDTH + GAP_X))));

/**
 * A left-to-right graph folded onto rows, like lines of text, once it is much wider than a screen: a chain of
 * fourteen plans is otherwise one strip a few pixels tall. Ranks keep their order, so reading across and then down
 * still follows the arrows; the arrow from the end of one row to the start of the next runs back across.
 */
function folded(chains: Corners): Corners {
  const ranks = [...new Set([...chains.values()].map(c => c.x))].sort((a, b) => a - b);
  const tall = Math.max(...[...chains.values()].map(c => c.y)) + NODE_HEIGHT + FOLD_GAP;
  const pitch = NODE_WIDTH + RANK_GAP;
  const across = Math.max(3, Math.ceil(Math.sqrt((1.8 * ranks.length * tall) / pitch)));
  if (ranks.length <= across) return chains;
  return new Map(
    [...chains].map(([ordinal, c]) => {
      const rank = ranks.indexOf(c.x);
      return [ordinal, { x: (rank % across) * pitch, y: c.y + Math.floor(rank / across) * tall }];
    }),
  );
}

/**
 * Chains by dagre, left to right, and the plans no arrow touches in rows beneath, as wide as the chains are.
 * Dagre alone stacks every unlinked plan in its first column, which in a project of mostly independent plans is
 * one tall strip beside a small graph.
 */
function adaptive(plans: DependencyPlan[], links: Link[]): Corners {
  const ids = new Set(plans.map(p => p.ordinal));
  const linked = new Set(links.filter(l => ids.has(l.from) && ids.has(l.to)).flatMap(l => [l.from, l.to]));
  const chains = folded(layered(plans.filter(p => linked.has(p.ordinal)), links, "LR"));
  const loners = plans.filter(p => !linked.has(p.ordinal));
  if (chains.size === 0) return rows(loners, columnsFor(loners.length));
  const corners = [...chains.values()];
  const width = Math.max(...corners.map(c => c.x)) + NODE_WIDTH;
  const bottom = Math.max(...corners.map(c => c.y)) + NODE_HEIGHT;
  const columns = Math.max(3, Math.floor((width + GAP_X) / (NODE_WIDTH + GAP_X)));
  return new Map([...chains, ...rows(loners, columns, bottom + GAP_Y * 2)]);
}

/**
 * A ring, clockwise from the top, wide enough that neighbours do not touch. Plans are ordered by group first, so a
 * chain's arrows stay short chords and do not all cross the middle.
 */
function circular(plans: DependencyPlan[], group: Map<string, string>): Corners {
  const order = [...plans].sort((a, b) => {
    const [ga, gb] = [group.get(a.ordinal) ?? a.ordinal, group.get(b.ordinal) ?? b.ordinal];
    return ga === gb ? a.ordinal.localeCompare(b.ordinal) : ga.localeCompare(gb);
  });
  const n = order.length;
  const radius = n < 2 ? 0 : (NODE_WIDTH + GAP_X) / (2 * Math.sin(Math.PI / n));
  return new Map(
    order.map((p, i) => {
      const angle = (2 * Math.PI * i) / n - Math.PI / 2;
      return [p.ordinal, { x: radius + radius * Math.cos(angle), y: radius + radius * Math.sin(angle) }];
    }),
  );
}

/** The top-left corner of every plan's box under the arrangement asked for. */
export function arrange(kind: LayoutKey, plans: DependencyPlan[], links: Link[], group: Map<string, string>): Corners {
  switch (kind) {
    case "right":
      return layered(plans, links, "LR");
    case "down":
      return layered(plans, links, "TB");
    case "circular":
      return circular(plans, group);
    case "grid":
      return rows(plans, columnsFor(plans.length));
    default:
      return adaptive(plans, links);
  }
}

export interface Box extends Point {
  width: number;
  height: number;
}

/** The rectangle around every box whose top-left corner is given. */
export function around(corners: Point[]): Box {
  const [left, top] = [Math.min(...corners.map(c => c.x)), Math.min(...corners.map(c => c.y))];
  return {
    x: left,
    y: top,
    width: Math.max(...corners.map(c => c.x)) + NODE_WIDTH - left,
    height: Math.max(...corners.map(c => c.y)) + NODE_HEIGHT - top,
  };
}

/** Where the straight line from the middle of `from` to the middle of `to` leaves `from`. */
export function exit(from: Box, to: Box): Point {
  const [cx, cy] = [from.x + from.width / 2, from.y + from.height / 2];
  const [dx, dy] = [to.x + to.width / 2 - cx, to.y + to.height / 2 - cy];
  if (dx === 0 && dy === 0) return { x: cx, y: cy };
  // The line reaches a side wall first when it is flatter than the box's own diagonal, a top or bottom wall otherwise.
  const scale = Math.min(dx === 0 ? Infinity : from.width / 2 / Math.abs(dx), dy === 0 ? Infinity : from.height / 2 / Math.abs(dy));
  return { x: cx + dx * scale, y: cy + dy * scale };
}

/** The SVG path of a straight arrow between two boxes, edge to edge. */
export function straight(source: Box, target: Box): string {
  const [a, b] = [exit(source, target), exit(target, source)];
  return `M ${a.x},${a.y} L ${b.x},${b.y}`;
}
