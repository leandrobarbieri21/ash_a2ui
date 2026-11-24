// Admin catalog 3.15: values recalculated from unsaved changes. A
// recalculated fieldDisplay binds `preview` (/ui/preview/<context>/<field>)
// and draws the server's result from it while there is one; the saveBar
// sends its `preview` envelope (preview_changes, quiet) whenever /ui/edits
// changes, emptied ones too; Discard clears /ui/preview; a whole-model
// refresh keeps it while it keeps the changes. The browser never works a
// value out.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, mergedCatalog, adminCatalog} from "./catalogs.mjs";
import {mountHook, sent} from "./harness.mjs";
import {feedback, keepUnsavedEdits, QUIET_ACTIONS} from "../../priv/js/ash_a2ui_protocol.js";

const {previewEntry, previewedProps, previewSpec, editsKey, discardEdits, PREVIEW_PATH} = adminCatalog;

async function settle() {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

function deep(root, selector, all = []) {
  for (const node of root.querySelectorAll(selector)) all.push(node);
  for (const node of root.querySelectorAll("*")) if (node.shadowRoot) deep(node.shadowRoot, selector, all);
  return all;
}

// --- the pure helpers -------------------------------------------------------

test("a preview replaces the value, and a steps field's steps", () => {
  assert.equal(previewEntry(null), null);
  assert.equal(previewEntry([]), null);

  const props = {label: "Notice by", value: "2027-05-31", preview: {value: "2027-12-02"}};
  assert.equal(previewedProps(props).value, "2027-12-02");
  assert.equal(previewedProps(props).label, "Notice by");
  assert.equal(previewedProps({value: "x"}).value, "x", "no preview: the stored value");

  const steps = {value: [], steps: [{label: "Ends", text: "2027-06-30"}], preview: {value: [], steps: [{label: "Ends", text: "2028-01-31"}]}};
  assert.equal(previewedProps(steps).steps[0].text, "2028-01-31");
});

test("the preview envelope, the edits key, and the quiet list", () => {
  const preview = {action: "preview_changes", context: {edits: {"@path": "/ui/edits"}}};
  assert.deepEqual(previewSpec({preview}).context, {edits: {"@path": "/ui/edits"}});
  assert.equal(previewSpec({preview}).name, "preview_changes");
  assert.equal(previewSpec({}), null);
  assert.equal(editsKey(undefined), editsKey({}));
  assert.ok(QUIET_ACTIONS.includes("preview_changes"));
});

test("Discard clears the preview with the changes", () => {
  const data = {ui: {edits: {terms: {}}, preview: {lease: {}}, edit_errors: {}}};
  const model = {
    get: (path) => path.split("/").filter(Boolean).reduce((node, key) => node?.[key], data),
    set: (path, value) => {
      const [, ui, key] = path.split("/");
      data[ui][key] = value;
    },
  };
  discardEdits(model);
  assert.deepEqual(data.ui.preview, {});
  assert.equal(PREVIEW_PATH, "/ui/preview");
});

test("a whole-model refresh keeps the preview while it keeps the changes", () => {
  const edits = {terms: {recordId: "l1", values: {rent: "1500"}}};
  const preview = {lease: {yearly: {value: "$18000"}}};
  const messages = [
    {version: "1.0", updateDataModel: {surfaceId: "l1", path: "/", value: {ui: {}, detail: {}}}},
    {version: "1.0", updateDataModel: {surfaceId: "l1", path: "/ui", value: {feedback: {}}}},
    {version: "1.0", updateDataModel: {surfaceId: "l1", path: "/ui/preview", value: {}}},
  ];

  const [whole, ui, cleared] = keepUnsavedEdits(messages, () => edits, () => preview);
  assert.deepEqual(whole.updateDataModel.value.ui.preview, preview);
  assert.deepEqual(ui.updateDataModel.value.preview, preview);
  assert.equal(cleared, messages[2], "the server's own write replaces it");

  // no changes kept: the preview is not kept either
  const [bare] = keepUnsavedEdits(messages, () => ({}), () => preview);
  assert.equal(bare, messages[0]);
});

// --- the elements ----------------------------------------------------------

async function mountPage() {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "l1",
        catalogId: admin.id,
        components: [
          {id: "root", component: "Column", children: ["rent", "yearly", "save_bar"]},
          {
            id: "rent",
            component: "fieldDisplay",
            label: "Rent",
            value: {"@path": "/detail/lease/rent"},
            edit: {component: "terms", field: "rent", recordId: {"@path": "/detail/lease/id"}, input: "integer"},
            editValue: {"@path": "/detail/lease/_edit_rent"},
            editVisible: {"@path": "/detail/lease/_editable_terms"},
            editDraft: {"@path": "/ui/edits/terms/values/rent"},
            editError: {"@path": "/ui/edit_errors/terms/rent"},
          },
          {
            id: "yearly",
            component: "fieldDisplay",
            label: "Yearly rent",
            note: "Calculated",
            value: {"@path": "/detail/lease/yearly_text"},
            preview: {"@path": "/ui/preview/lease/yearly_text"},
          },
          {
            id: "save_bar",
            component: "saveBar",
            message: "You have unsaved changes",
            saveLabel: "Save changes",
            discardLabel: "Discard changes",
            edits: {"@path": "/ui/edits"},
            record: {"@path": "/detail/lease"},
            reviews: [],
            editReviews: false,
            action: {action: "save_changes", context: {edits: {"@path": "/ui/edits"}, recordId: {"@path": "/detail/lease/id"}}},
            preview: {action: "preview_changes", context: {edits: {"@path": "/ui/edits"}}},
          },
        ],
        dataModel: {
          detail: {lease: {id: "l1", rent: 1000, _edit_rent: 1000, _editable_terms: true, yearly_text: "$12000 a year"}},
          ui: {feedback: feedback()},
        },
      },
    },
  ]);
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("l1");
  await settle();
  const [rent, yearly] = deep(element, "ash-admin-field-display");
  const [saveBar] = deep(element, "ash-admin-save-bar");
  return {hook, rent, yearly, saveBar, model: hook.processor.getSurface("l1").dataModel};
}

const previews = (hook) =>
  sent(hook)
    .map((message) => message.callAgentFunction?.callFunction?.args)
    .filter((args) => args?.name === "preview_changes");

async function keep(field, value) {
  field.openEdit();
  await settle();
  const control = field.renderRoot.querySelector("[data-a2ui-edit-input]");
  control.value = value;
  control.dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}));
  await settle();
}

test("nothing is sent while nothing changed", async () => {
  const {hook} = await mountPage();
  assert.equal(previews(hook).length, 0);
});

test("a kept change sends the changes for a preview, quietly", async () => {
  const {hook, rent, model} = await mountPage();
  await keep(rent, "1500");

  const [call] = previews(hook);
  assert.ok(call, "preview_changes is sent");
  assert.deepEqual(call.context.edits, {terms: {recordId: "l1", values: {rent: "1500"}}});
  assert.notEqual(model.get("/ui/feedback/kind"), "pending", "no pending state");
});

test("the field draws the server's preview, and the stored value again once it goes", async () => {
  const {hook, yearly} = await mountPage();
  assert.match(yearly.renderRoot.textContent, /\$12000 a year/);

  hook.processMessages([
    {version: "1.0", updateDataModel: {surfaceId: "l1", path: "/ui/preview", value: {lease: {yearly_text: {value: "$18000 a year"}}}}},
  ]);
  await settle();
  assert.match(yearly.renderRoot.textContent, /\$18000 a year/);
  assert.match(yearly.renderRoot.textContent, /Calculated/);

  hook.processMessages([{version: "1.0", updateDataModel: {surfaceId: "l1", path: "/ui/preview", value: {}}}]);
  await settle();
  assert.match(yearly.renderRoot.textContent, /\$12000 a year/);
});

test("Discard clears the preview at once and sends the emptied changes", async () => {
  const {hook, rent, yearly, saveBar, model} = await mountPage();
  await keep(rent, "1500");
  hook.processMessages([
    {version: "1.0", updateDataModel: {surfaceId: "l1", path: "/ui/preview", value: {lease: {yearly_text: {value: "$18000 a year"}}}}},
  ]);
  await settle();

  saveBar.onDiscard();
  await settle();
  assert.deepEqual(model.get("/ui/preview"), {});
  assert.match(yearly.renderRoot.textContent, /\$12000 a year/);

  const calls = previews(hook);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls.at(-1).context.edits, {});
});

test("the same changes are not sent twice", async () => {
  const {hook, rent, model} = await mountPage();
  await keep(rent, "1500");
  // an unrelated write re-renders the bar with the same changes
  model.set("/detail/lease/rent", 1000);
  await settle();
  assert.equal(previews(hook).length, 1);
});
