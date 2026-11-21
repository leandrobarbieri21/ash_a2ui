// Admin catalog 3.12: a masked field. The stock renderer draws the value
// (the masked word) as plain text — ignoring format, link, badge,
// emptyText and hideWhenEmpty — marks the element data-a2ui-masked, and
// gives the bound reason as its title and accessible description. The
// same per cell on a dataGrid column whose masked binding resolves.

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

function deepAll(root, selector) {
  const found = [...root.querySelectorAll(selector)];
  for (const node of root.querySelectorAll("*")) {
    if (node.shadowRoot) found.push(...deepAll(node.shadowRoot, selector));
  }
  return found;
}

const reason = "You do not have access to this value.";

async function mountSurface(components, dataModel) {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components,
        dataModel: {ui: {feedback: feedback()}, ...dataModel},
      },
    },
  ]);
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("s1");
  await settle();
  return element;
}

function mountField(props, record) {
  const display = {id: "rate", component: "fieldDisplay", label: "Rate", ...props};
  return mountSurface(
    [{id: "root", component: "Column", children: ["rate"]}, display],
    {detail: {lease: record}},
  );
}

const maskedEl = (element) => deep(element, "[data-a2ui-masked]");

test("a fieldDisplay whose masked binding resolves draws the value masked", async () => {
  const element = await mountField(
    {
      value: {"@path": "/detail/lease/rate"},
      masked: {"@path": "/detail/lease/_masked/rate"},
    },
    {rate: "Hidden", _masked: {rate: reason}},
  );

  const el = maskedEl(element);
  assert.ok(el, "the masked element draws");
  assert.equal(el.textContent.trim(), "Hidden");
  assert.equal(el.getAttribute("title"), reason);
  assert.equal(el.getAttribute("aria-description"), reason);
});

test("format, badge, link and emptyText are ignored on a masked field", async () => {
  const element = await mountField(
    {
      value: {"@path": "/detail/lease/rate"},
      masked: {"@path": "/detail/lease/_masked/rate"},
      format: "number",
      badge: {"@path": "/detail/lease/_badge_rate"},
      badgeTone: {"@path": "/detail/lease/_badge_tone_rate"},
      link: {"@path": "/detail/lease/_links/rate"},
      emptyText: "Not set",
    },
    {rate: "Hidden", _badge_rate: "Open", _masked: {rate: reason}},
  );

  const el = maskedEl(element);
  assert.ok(el);
  // a number format would not pass "Hidden" through unchanged
  assert.equal(el.textContent.trim(), "Hidden");
  assert.equal(deep(element, ".am-badge"), null);
  assert.equal(deep(element, "a"), null);
});

test("hideWhenEmpty is ignored: an empty masked value still draws", async () => {
  const element = await mountField(
    {
      value: {"@path": "/detail/lease/rate"},
      masked: {"@path": "/detail/lease/_masked/rate"},
      hideWhenEmpty: true,
    },
    {rate: "", _masked: {rate: reason}},
  );

  assert.ok(maskedEl(element), "the masked element draws while empty");
});

test("without a masked reason the field draws as before", async () => {
  const element = await mountField(
    {
      value: {"@path": "/detail/lease/rate"},
      format: "number",
      hideWhenEmpty: false,
    },
    {rate: 1200.5},
  );

  assert.equal(maskedEl(element), null);
  const field = deep(element, "ash-admin-field-display");
  const text = field.renderRoot.textContent.trim();
  // the value drew (formatted per the locale's number rules), unhidden
  assert.match(text, /1[.,]200[.,]5/);
});

async function mountGrid(column, rows) {
  return mountSurface(
    [
      {id: "root", component: "Column", children: ["grid"]},
      {
        id: "grid",
        component: "dataGrid",
        columns: [{label: "Rate", path: "rate", ...column}],
        rows: {"@path": "/records"},
        rowId: "id",
      },
    ],
    {records: rows},
  );
}

test("a dataGrid cell whose masked binding resolves draws masked", async () => {
  const element = await mountGrid(
    {masked: {path: "_masked/rate"}, format: "number"},
    [
      {id: "r1", rate: "Hidden", _masked: {rate: reason}},
      {id: "r2", rate: 800, _masked: {}},
    ],
  );

  // The grid draws each row twice, as a table row and as a card (the
  // layout shows one): one mark per layout, on the masked row only.
  const masked = deepAll(element, "tr [data-a2ui-masked]");
  assert.equal(masked.length, 1, "only the masked row draws the mark");
  assert.equal(deepAll(element, "li.card [data-a2ui-masked]").length, 1);
  assert.equal(masked[0].textContent.trim(), "Hidden");
  assert.equal(masked[0].getAttribute("title"), reason);
  assert.equal(masked[0].getAttribute("aria-description"), reason);

  // the unmasked cell keeps its number format
  const grid = deep(element, "ash-admin-data-grid");
  assert.ok(grid.renderRoot.textContent.includes("800"));
});
