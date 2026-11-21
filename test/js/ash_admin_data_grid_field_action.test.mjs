// 3.9: the stock dataGrid draws a column's field action as a quiet button on
// the value's line, in each row that offers it (actionVisible, row-relative),
// and sends it like a row action: the entry's bindings resolved against the
// row, the button busy until the outcome, the row's own click untouched.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, mergedCatalog} from "./catalogs.mjs";
import {mountHook, sent} from "./harness.mjs";
import {feedback} from "../../priv/js/ash_a2ui_protocol.js";

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

const pending = {state: "pending", stateLabel: "Not reviewed", page: 3, pageLabel: "p. 3"};

const rows = [
  {id: "r1", service: "Snow removal", price: "$1,200", _review_price: pending, _action_price: true},
  {id: "r2", service: "Landscaping", price: "$800", _review_price: null, _action_price: false},
];

const action = {
  label: "Mark as reviewed",
  icon: "check",
  action: "field_action",
  context: {
    component: "lines",
    field: "price",
    recordId: {"@path": "id"},
    contexts: {"@path": "/context"},
  },
};

async function mountGrid() {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [
          {id: "root", component: "Column", children: ["grid"]},
          {
            id: "grid",
            component: "dataGrid",
            columns: [
              {label: "Service", path: "service"},
              {
                label: "Price",
                path: "price",
                review: {path: "_review_price"},
                action,
                actionVisible: {path: "_action_price"},
              },
            ],
            rows: {"@path": "/records"},
            rowId: "id",
          },
        ],
        dataModel: {
          records: rows,
          context: {contract: {value: "c1", label: "Snow"}},
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
const button = (row) => row.querySelector("[data-a2ui-action='field_action'] button");

test("a row that offers the action draws its button after the review; one that does not, none", async () => {
  const {grid} = await mountGrid();

  const offered = button(tableRow(grid, "r1"));
  assert.ok(offered);
  assert.equal(offered.textContent.trim(), "Mark as reviewed");
  assert.equal(button(tableRow(grid, "r2")), null);
});

test("a click sends the field_action ashAction with the row's id and the selections", async () => {
  const {hook, grid} = await mountGrid();
  button(tableRow(grid, "r1")).click();
  await settle();

  const calls = sent(hook).map((message) => message.callAgentFunction?.callFunction?.args).filter(Boolean);
  const call = calls.find((args) => args.name === "field_action");
  assert.ok(call, "the field action was sent");
  assert.deepEqual(call.context, {
    component: "lines",
    field: "price",
    recordId: "r1",
    contexts: {contract: {value: "c1", label: "Snow"}},
  });
  assert.equal(button(tableRow(grid, "r1")).getAttribute("aria-busy"), "true");
});

test("the cards below the table draw the same button", async () => {
  const {grid} = await mountGrid();
  const card = grid.renderRoot.querySelector('.grid-cards [data-a2ui-row-id="r1"]');
  assert.ok(button(card));
  const other = grid.renderRoot.querySelector('.grid-cards [data-a2ui-row-id="r2"]');
  assert.equal(button(other), null);
});
