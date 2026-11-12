/**
 * Pure geometry for the live diagram: keeping edge labels and marker badges
 * from drawing on top of each other or on top of a node.
 *
 * Mermaid lays out the graph but only avoids overlap between a label and the
 * label of another edge when the layout leaves room for it; a state chart
 * with two transitions leaving one state, or a loop beside an exit, puts two
 * labels in the same place. The marker layer is ours, so it is placed here
 * with the same rules.
 *
 * Everything works on plain rectangles `{x, y, width, height}` (pixels, one
 * shared origin), so the rules are unit-tested without a browser
 * (`test/js/ash_a2ui_diagram_layout.test.mjs`).
 */

/** True when the two rectangles overlap, or come closer than `gap`. */
export function overlaps(a, b, gap = 0) {
  return (
    a.x < b.x + b.width + gap &&
    b.x < a.x + a.width + gap &&
    a.y < b.y + b.height + gap &&
    b.y < a.y + a.height + gap
  );
}

/** Every rectangle of `rects` that overlaps another (by index pair). */
export function collisions(rects, gap = 0) {
  const pairs = [];
  for (let i = 0; i < rects.length; i++) {
    for (let j = i + 1; j < rects.length; j++) {
      if (overlaps(rects[i], rects[j], gap)) pairs.push([i, j]);
    }
  }
  return pairs;
}

function moved(rect, dx, dy) {
  return {...rect, x: rect.x + dx, y: rect.y + dy};
}

// Offsets around the origin, nearest first, vertical moves before horizontal
// ones at the same distance (a label shifted up or down stays on its edge's
// line far better than one shifted along it).
function candidateOffsets(step, radius) {
  const offsets = [];
  const rings = Math.ceil(radius / step);
  for (let ix = -rings; ix <= rings; ix++) {
    for (let iy = -rings; iy <= rings; iy++) {
      if (ix === 0 && iy === 0) continue;
      offsets.push({dx: ix * step, dy: iy * step, d: ix * ix + iy * iy, horizontal: iy === 0 ? 1 : 0});
    }
  }
  return offsets.sort((a, b) => a.d - b.d || a.horizontal - b.horizontal || a.dy - b.dy || a.dx - b.dx);
}

/**
 * Moves `items` (edge labels) the shortest distance that leaves each clear of
 * every `obstacle` (nodes, markers) and of every other item, keeping `gap`
 * pixels between them.
 *
 * `items` are `{id, x, y, width, height}`; the result has one `{id, dx, dy}`
 * per item, `0, 0` when it can stay. An item that fits nowhere within
 * `radius` stays where it is (a diagram that cannot be made clear is better
 * left as mermaid drew it than scattered).
 */
export function separate(items, obstacles, {gap = 4, step = 4, radius = 160} = {}) {
  const offsets = candidateOffsets(step, radius);
  const placed = [];
  const result = [];

  // Reading order, so the outcome does not depend on the DOM order mermaid used.
  const order = items
    .map((item, index) => ({item, index}))
    .sort((a, b) => a.item.y - b.item.y || a.item.x - b.item.x || a.index - b.index);

  for (const {item} of order) {
    const clear = (rect) =>
      !obstacles.some((obstacle) => overlaps(rect, obstacle, gap)) &&
      !placed.some((other) => overlaps(rect, other, gap));

    let chosen = {dx: 0, dy: 0};
    if (!clear(item)) {
      const fit = offsets.find((offset) => clear(moved(item, offset.dx, offset.dy)));
      if (fit) chosen = {dx: fit.dx, dy: fit.dy};
    }
    placed.push(moved(item, chosen.dx, chosen.dy));
    result.push({id: item.id, dx: chosen.dx, dy: chosen.dy});
  }

  return items.map((item) => result.find((entry) => entry.id === item.id));
}

/**
 * Where the marker badges of several nodes go. Each node's badges form one
 * compact group (rows no wider than the node), which starts beneath its node
 * and is moved the shortest distance that keeps it off every node (its own
 * included) and off the other groups, so a badge never covers a state box,
 * however many are marked on it and however tight the layout.
 *
 * `groups` are `{id, node, count}` (`node` a rectangle); the result maps each
 * id to its badge centres, `{x, y}` per marker, in order.
 */
export function placeMarkerGroups(groups, nodes, {size = 32, gap = 4, offset = 4, radius = 400} = {}) {
  const shapes = groups.map(({id, node, count}) => {
    const columns = Math.max(1, Math.min(count, Math.floor((node.width + gap) / (size + gap))));
    const rows = Math.ceil(count / columns);
    return {
      id,
      count,
      columns,
      x: node.x + (node.width - (columns * size + (columns - 1) * gap)) / 2,
      y: node.y + node.height + offset,
      width: columns * size + (columns - 1) * gap,
      height: rows * size + (rows - 1) * gap,
    };
  });

  const moves = separate(shapes, nodes, {gap: 2, step: 4, radius});
  const placed = {};
  shapes.forEach((shape, index) => {
    const left = shape.x + moves[index].dx;
    const top = shape.y + moves[index].dy;
    placed[shape.id] = Array.from({length: shape.count}, (_, i) => ({
      x: left + (i % shape.columns) * (size + gap) + size / 2,
      y: top + Math.floor(i / shape.columns) * (size + gap) + size / 2,
    }));
  });
  return placed;
}
