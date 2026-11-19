// 3.3: the stock dataGrid draws a review field's review in its cell, as the
// fieldDisplay does on a detail card: the state in words beside the page
// tag (a link when the review has an href), the value highlighted while
// pending. A column's subtitle draws its own review (subtitle.reviewPath).

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

const pending = {
  state: "pending",
  stateLabel: "Not reviewed",
  page: 3,
  pageLabel: "p. 3",
  href: "#citation=lines.0.price",
  quote: "Monthly fee: $1,200",
};

const reviewed = {state: "reviewed", stateLabel: "Reviewed", page: 2, pageLabel: "p. 2"};

const rows = [
  {id: "r1", service: "Snow removal", price: "$1,200", period: "Jan – Mar", _review_price: pending, _review_period: reviewed},
  {id: "r2", service: "Landscaping", price: "$800", period: "Apr – Oct", _review_price: null, _review_period: null},
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
              {label: "Service", path: "service", subtitle: {path: "period", reviewPath: "_review_period"}},
              {label: "Price", path: "price", review: {path: "_review_price"}},
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

const tableRow = (grid, id) => grid.renderRoot.querySelector(`tr[data-a2ui-row-id="${id}"]`);

test("a pending value's cell writes its state beside a page tag linking to the source", async () => {
  const grid = await mountGrid();
  const price = tableRow(grid, "r1").querySelectorAll("td")[0];

  assert.equal(price.querySelector(".am-cell-value").dataset.review, "pending");
  assert.equal(price.querySelector(".am-cell-value").textContent.trim(), "$1,200");

  const review = price.querySelector(".am-cell-review");
  assert.equal(review.querySelector(".am-badge").dataset.tone, "warning");
  assert.equal(review.querySelector(".am-badge").textContent.trim(), "Not reviewed");

  const page = review.querySelector("a.am-cell-review-page");
  assert.equal(page.getAttribute("href"), "#citation=lines.0.price");
  assert.equal(page.textContent.trim(), "p. 3");
  assert.equal(page.getAttribute("title"), "Monthly fee: $1,200");
});

test("a subtitle draws its own review: reviewed, its page a plain tag without an href", async () => {
  const grid = await mountGrid();
  const service = tableRow(grid, "r1").querySelector("th");
  const sub = service.querySelector(".am-cell-sub");

  assert.equal(sub.querySelector(".am-cell-value").textContent.trim(), "Jan – Mar");
  assert.equal(sub.querySelector(".am-cell-value").dataset.review, "reviewed");
  assert.equal(sub.querySelector(".am-badge").dataset.tone, "success");
  assert.equal(sub.querySelector(".am-badge").textContent.trim(), "Reviewed");
  assert.equal(sub.querySelector("a"), null);
  assert.equal(sub.querySelector("span.am-cell-review-page").textContent.trim(), "p. 2");

  // The service's own value carries no review.
  assert.equal(service.querySelector(".am-cell-line .am-cell-review"), null);
});

test("a row without a review draws the value alone", async () => {
  const grid = await mountGrid();
  const row = tableRow(grid, "r2");

  assert.equal(row.querySelector(".am-cell-review"), null);
  assert.equal(row.querySelector("[data-review]"), null);
  assert.equal(row.querySelectorAll("td")[0].textContent.trim(), "$800");
  assert.equal(row.querySelector(".am-cell-sub").textContent.trim(), "Apr – Oct");
});

test("card rows draw the same review", async () => {
  const grid = await mountGrid();
  const card = grid.renderRoot.querySelector('.grid-cards [data-a2ui-row-id="r1"]');

  const links = [...card.querySelectorAll("a.am-cell-review-page")].map((a) => a.getAttribute("href"));
  assert.deepEqual(links, ["#citation=lines.0.price"]);
  assert.equal(card.querySelectorAll(".am-cell-review").length, 2);
});
