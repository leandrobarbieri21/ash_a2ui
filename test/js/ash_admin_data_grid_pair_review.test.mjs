// 3.10: a pairs column bound to its row's items (`items`) draws one labeled
// line per item, each with its own review after the value and, while the
// item offers it, the column's pairAction as a quiet button, sent like a row
// action with the item's key added to its context. A payload without
// `items` draws the pairs as before.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, adminCatalog, mergedCatalog} from "./catalogs.mjs";
import {mountHook, sent} from "./harness.mjs";
import {feedback} from "../../priv/js/ash_a2ui_protocol.js";

const {pairActionEntry, pairActionOffered, pairItems, rowReviews} = adminCatalog;

async function settle() {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

function deep(root, selector) {
  const found = root.querySelector(selector);
  if (found) return found;
  for (const node of root.querySelectorAll("*")) {
    const inner = node.shadowRoot && deep(node.shadowRoot, selector);
    if (inner) return inner;
  }
  return null;
}

const pending = {state: "pending", stateLabel: "Not reviewed", page: 3, pageLabel: "p. 3", href: "#doc=n.0.0"};
const reviewed = {state: "reviewed", stateLabel: "Reviewed", page: 4, pageLabel: "p. 4"};

const rows = [
  {
    id: "n1",
    title: "Termination",
    facts: [{term: "Notice", value: "60 days"}],
    _pairs_facts: [
      {term: "Notice", value: "60 days", key: "0", review: pending, action: true},
      {term: "Cause", value: "Breach", key: "1", review: reviewed, action: false},
    ],
  },
];

const pairAction = {
  label: "Mark as reviewed",
  icon: "check",
  action: "field_action",
  context: {
    component: "notes",
    field: "facts",
    recordId: {"@path": "id"},
    contexts: {"@path": "/context"},
  },
};

const factsColumn = {label: "Facts", path: "facts", pairs: true, items: {path: "_pairs_facts"}, pairAction};

async function mountGrid(columns = [{label: "Title", path: "title"}, factsColumn]) {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [
          {id: "root", component: "Column", children: ["grid"]},
          {id: "grid", component: "dataGrid", columns, rows: {"@path": "/records"}, rowId: "id"},
        ],
        dataModel: {
          records: rows,
          context: {dossier: {value: "d1", label: "Harbour"}},
          ui: {feedback: feedback()},
        },
      },
    },
  ]);
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("s1");
  await settle();
  const grid = deep(element, "ash-admin-data-grid");
  assert.ok(grid, "the grid renders");
  return {hook, grid};
}

const tableRow = (grid, id) => grid.renderRoot.querySelector(`tr[data-a2ui-row-id="${id}"]`);
const pairs = (row) => [...row.querySelectorAll(".am-pair")];
const button = (pair) => pair.querySelector("[data-a2ui-action='field_action'] button");

test("the helpers read the items, the offer and the entry sent", () => {
  assert.deepEqual(
    pairItems(rows[0], factsColumn).map((item) => item.key),
    ["0", "1"],
  );
  assert.deepEqual(pairItems(rows[0], {path: "facts", pairs: true}), []);
  assert.equal(pairActionOffered(factsColumn, rows[0]._pairs_facts[0]), true);
  assert.equal(pairActionOffered(factsColumn, rows[0]._pairs_facts[1]), false);
  assert.equal(pairActionOffered(factsColumn, {term: "x", action: true}), false);
  assert.equal(pairActionEntry(factsColumn, rows[0]._pairs_facts[0]).context.item, "0");
  // each item's review is one of the row's, for the document pane's links
  assert.deepEqual(
    rowReviews(rows[0], [factsColumn]).map((review) => review.state),
    ["pending", "reviewed"],
  );
});

test("each item draws its term, value and review; only an offering item its button", async () => {
  const {grid} = await mountGrid();
  const [notice, cause] = pairs(tableRow(grid, "n1"));

  assert.equal(notice.querySelector("dt").textContent.trim(), "Notice");
  assert.match(notice.querySelector("dd").textContent, /60 days/);
  assert.match(notice.textContent, /p\. 3/);
  assert.equal(notice.getAttribute("data-a2ui-region"), "#doc=n.0.0");
  assert.equal(notice.querySelector(".am-cell-value").getAttribute("data-review"), "pending");
  assert.equal(button(notice).textContent.trim(), "Mark as reviewed");

  assert.match(cause.textContent, /p\. 4/);
  assert.equal(button(cause), null);
});

test("a click sends the field_action ashAction with the row's id and the item's key", async () => {
  const {hook, grid} = await mountGrid();
  button(pairs(tableRow(grid, "n1"))[0]).click();
  await settle();

  const calls = sent(hook).map((message) => message.callAgentFunction?.callFunction?.args).filter(Boolean);
  const call = calls.find((args) => args.name === "field_action");
  assert.ok(call, "the field action was sent");
  assert.deepEqual(call.context, {
    component: "notes",
    field: "facts",
    recordId: "n1",
    item: "0",
    contexts: {dossier: {value: "d1", label: "Harbour"}},
  });
  assert.equal(button(pairs(tableRow(grid, "n1"))[0]).getAttribute("aria-busy"), "true");
});

test("without items, the pairs column draws its raw value as before", async () => {
  const {grid} = await mountGrid([{label: "Title", path: "title"}, {label: "Facts", path: "facts", pairs: true}]);
  assert.deepEqual(pairs(tableRow(grid, "n1")), []);
});
