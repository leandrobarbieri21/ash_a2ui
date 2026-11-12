import test from "node:test";
import assert from "node:assert/strict";

import {collisions, overlaps, placeMarkerGroups, separate} from "../../priv/js/ash_a2ui_diagram_layout.js";

const rect = (id, x, y, width = 80, height = 20) => ({id, x, y, width, height});
const apply = (item, move) => ({...item, x: item.x + move.dx, y: item.y + move.dy});

function settle(items, obstacles = [], options) {
  const moves = separate(items, obstacles, options);
  return items.map((item, index) => apply(item, moves[index]));
}

test("labels that do not collide stay where mermaid put them", () => {
  const items = [rect("a", 0, 0), rect("b", 200, 0)];
  assert.deepEqual(separate(items, []), [
    {id: "a", dx: 0, dy: 0},
    {id: "b", dx: 0, dy: 0},
  ]);
});

test("two labels drawn in the same place are pulled apart", () => {
  const items = [rect("withdraw", 100, 50), rect("open the tender", 100, 50)];
  const out = settle(items);

  assert.equal(collisions(out, 4).length, 0);
});

test("a label never overlaps a node, and keeps the gap", () => {
  const node = rect("node", 90, 40, 120, 60);
  const items = [rect("label", 100, 50)];
  const [out] = settle(items, [node]);

  assert.equal(overlaps(out, node, 4), false);
});

test("a crowd of labels on one spot ends with no overlaps", () => {
  const items = Array.from({length: 7}, (_, i) => rect(`l${i}`, 300, 120, 90 + i * 6, 18));
  const nodes = [rect("n1", 250, 60, 120, 40), rect("n2", 250, 200, 120, 40)];
  const out = settle(items, nodes);

  assert.equal(collisions(out, 4).length, 0);
  for (const label of out) for (const node of nodes) assert.equal(overlaps(label, node, 4), false);
});

test("the result does not depend on the order the labels come in", () => {
  const a = rect("a", 50, 50);
  const b = rect("b", 60, 55);
  const forward = settle([a, b]);
  const backward = settle([b, a]);

  assert.deepEqual(
    forward.map(({id, x, y}) => [id, x, y]).sort(),
    backward.map(({id, x, y}) => [id, x, y]).sort(),
  );
});

test("a label that fits nowhere within the radius stays put", () => {
  const wall = rect("wall", -1000, -1000, 4000, 4000);
  const [move] = separate([rect("l", 0, 0)], [wall], {radius: 20});

  assert.deepEqual(move, {id: "l", dx: 0, dy: 0});
});

const badgesOf = (slots, size = 32) =>
  slots.map((slot) => ({x: slot.x - size / 2, y: slot.y - size / 2, width: size, height: size}));

test("marker badges start beneath their node, in rows no wider than it", () => {
  const node = {x: 100, y: 50, width: 120, height: 40};
  const placed = placeMarkerGroups([{id: "n", node, count: 7}], [node]);
  const badges = badgesOf(placed.n);

  assert.equal(badges.length, 7);
  assert.equal(collisions(badges, 0).length, 0);
  for (const badge of badges) assert.equal(overlaps(badge, node), false);
});

test("badges never cover a node, even when the next node is right below", () => {
  // The tendering chart: Planning with four markers, Out to tender 30px under it.
  const planning = {x: 100, y: 50, width: 70, height: 30};
  const tender = {x: 110, y: 110, width: 90, height: 30};
  const placed = placeMarkerGroups([{id: "planning", node: planning, count: 4}], [planning, tender]);
  const badges = badgesOf(placed.planning);

  assert.equal(badges.length, 4);
  assert.equal(collisions(badges, 0).length, 0);
  for (const badge of badges) {
    assert.equal(overlaps(badge, planning), false);
    assert.equal(overlaps(badge, tender), false);
  }
});

test("badge groups of different nodes never overlap each other", () => {
  const a = {x: 100, y: 50, width: 70, height: 30};
  const b = {x: 110, y: 100, width: 70, height: 30};
  const placed = placeMarkerGroups(
    [
      {id: "a", node: a, count: 3},
      {id: "b", node: b, count: 3},
    ],
    [a, b],
  );
  const all = [...badgesOf(placed.a), ...badgesOf(placed.b)];

  assert.equal(collisions(all, 0).length, 0);
  for (const badge of all) {
    assert.equal(overlaps(badge, a), false);
    assert.equal(overlaps(badge, b), false);
  }
});

test("a node narrower than one badge still gets a badge per marker", () => {
  const node = {x: 0, y: 0, width: 10, height: 10};
  const placed = placeMarkerGroups([{id: "n", node, count: 3}], [node]);

  assert.equal(placed.n.length, 3);
  assert.equal(collisions(badgesOf(placed.n), 0).length, 0);
});
