// Every cell of the stock dataGrid, in a table row and in a narrow-layout
// card, names the field it shows in data-a2ui-column, so a test finds a cell
// by what it shows and not by its position.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, mergedCatalog} from "./catalogs.mjs";
import {mountHook} from "./harness.mjs";
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

const rows = [
  {id: "r1", service: "Snow removal", price: "$1,200", period: "Jan – Mar"},
  {id: "r2", service: "Landscaping", price: "$800", period: "Apr – Oct"},
];

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
              {label: "Price", path: "price"},
              {label: "Period", path: "period"},
            ],
            rows: {"@path": "/records"},
            rowId: "id",
          },
        ],
        dataModel: {records: rows, ui: {feedback: feedback()}},
      },
    },
  ]);
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("s1");
  await settle();
  const grid = deep(element, "ash-admin-data-grid");
  assert.ok(grid, "the grid renders");
  return grid;
}

test("each cell of a table row carries the field it shows", async () => {
  const grid = await mountGrid();
  const row = grid.renderRoot.querySelector('tr[data-a2ui-row-id="r1"]');

  const columns = [...row.querySelectorAll("[data-a2ui-column]")].map((cell) =>
    cell.getAttribute("data-a2ui-column"),
  );
  assert.deepEqual(columns, ["service", "price", "period"]);
  assert.equal(row.querySelector('[data-a2ui-column="price"]').textContent.trim(), "$1,200");
});

test("each field of a card carries the field it shows", async () => {
  const grid = await mountGrid();
  const card = grid.renderRoot.querySelector('.grid-cards [data-a2ui-row-id="r2"]');

  assert.equal(card.querySelector('[data-a2ui-column="period"]').textContent.trim(), "Apr – Oct");
  assert.equal(card.querySelectorAll("[data-a2ui-column]").length, 3);
});
