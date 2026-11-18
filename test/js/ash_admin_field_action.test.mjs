// Admin catalog 3.2: a fieldDisplay's field action. The stock element draws
// the button only while the record offers it (`actionVisible`), and a click
// sends the entry as the ash_a2ui catalog's ashAction, its bindings
// resolved against the data model.

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

const entry = {
  label: "Mark as checked",
  icon: "check",
  action: "field_action",
  context: {
    component: "facts",
    field: "title",
    recordId: {"@path": "/detail/finding/id"},
    contexts: {"@path": "/context"},
  },
};

async function mountField({visible = true, bound = true} = {}) {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  const display = {
    id: "title",
    component: "fieldDisplay",
    label: "Title",
    value: {"@path": "/detail/finding/title"},
    action: entry,
  };
  if (bound) display.actionVisible = {"@path": "/detail/finding/_action_title"};

  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [{id: "root", component: "Column", children: ["title"]}, display],
        dataModel: {
          detail: {finding: {id: "f1", title: "Annual fee", _action_title: visible}},
          context: {finding: {value: "f1", label: "Annual fee"}},
          ui: {feedback: feedback()},
        },
      },
    },
  ]);
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("s1");
  await settle();
  const field = deep(element, "ash-admin-field-display");
  assert.ok(field, "the field renders");
  return {hook, field};
}

const button = (field) => field.renderRoot.querySelector("[data-a2ui-action='field_action'] button");

const write = (hook, path, value) =>
  hook.processMessages([{version: "1.0", updateDataModel: {surfaceId: "s1", path, value}}]);

test("the button shows while the record offers the action, and goes when it stops", async () => {
  const {hook, field} = await mountField();
  assert.equal(button(field)?.textContent.trim(), "Mark as checked");

  write(hook, "/detail/finding/_action_title", false);
  await settle();
  assert.equal(button(field), null);
});

test("no button on a record that does not offer it", async () => {
  const {field} = await mountField({visible: false});
  assert.equal(button(field), null);
});

test("an unbound gate always offers it", async () => {
  const {field} = await mountField({bound: false});
  assert.ok(button(field));
});

test("a click sends the field_action ashAction with the record and selections resolved", async () => {
  const {hook, field} = await mountField();
  button(field).click();
  await settle();

  const calls = sent(hook).map((message) => message.callAgentFunction?.callFunction?.args).filter(Boolean);
  const call = calls.find((args) => args.name === "field_action");
  assert.ok(call, "the field action was sent");
  assert.deepEqual(call.context, {
    component: "facts",
    field: "title",
    recordId: "f1",
    contexts: {finding: {value: "f1", label: "Annual fee"}},
  });
  assert.equal(button(field).getAttribute("aria-busy"), "true");
});
