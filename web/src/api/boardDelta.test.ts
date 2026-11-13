import { appliesTo, applyDelta } from "./boardDelta";
import { loadFixtureBoard } from "./client";

const board = () => loadFixtureBoard();
const me = () => board().me;
const planKey = (ord: string) => `plan/${me().node.id}/${me().node.checkout}/${ord}`;

it("applies only onto the version it names", () => {
  expect(appliesTo(1, { base: 1, version: 2, upsert: [], remove: [] })).toBe(true);
  expect(appliesTo(2, { base: 1, version: 2, upsert: [], remove: [] })).toBe(false);
  expect(appliesTo(null, { base: 1, version: 2, upsert: [], remove: [] })).toBe(false);
});

it("returns the same board for an empty delta, with the new version", () => {
  const out = applyDelta(board(), { base: 1, version: 2, upsert: [], remove: [] });
  expect(out.me).toEqual(me());
  expect(out.others).toEqual(board().others);
  expect(out.version).toBe(2);
});

it("replaces an upserted plan and drops a removed one, keeping the order", () => {
  const before = me().plans;
  const [first, second] = before;
  const out = applyDelta(board(), {
    base: 1, version: 2,
    upsert: [{ key: planKey(first.ordinal), value: { ...first, cost: 42 } }],
    remove: [planKey(second.ordinal)],
  });
  expect(out.me?.plans.map(p => p.ordinal)).toEqual(before.filter(p => p !== second).map(p => p.ordinal));
  expect(out.me?.plans[0].cost).toBe(42);
});

it("keeps the server's bytewise order of other machines, upper-case hosts first", () => {
  const other = board().others[0];
  const node = (host: string) => ({ ...other.node, id: host, host, me: false });
  const b = { ...board(), others: [{ ...other, node: node("Zeta"), plans: [] }, { ...other, node: node("alpha"), plans: [] }] };
  const out = applyDelta(b, { base: 1, version: 2, upsert: [], remove: [] });
  expect(out.others.map(s => s.node.host)).toEqual(["Zeta", "alpha"]);
});

it("removes a node and its plans", () => {
  const other = board().others[0];
  const out = applyDelta(board(), { base: 1, version: 2, upsert: [], remove: [`node/${other.node.id}/${other.node.checkout}`] });
  expect(out.others).toEqual([]);
  expect(out.me).toEqual(me());
});
