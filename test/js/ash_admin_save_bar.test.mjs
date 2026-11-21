// Admin catalog 3.11: editing a record in place, saved by a save bar. A
// fieldDisplay's `edit` opens its value as an input; Enter or leaving it
// writes the change to /ui/edits (Escape drops it); the saveBar shows while
// a change waits, counts the fields under review still waiting, discards,
// or sends save_changes, through its confirm dialog while fields wait. A
// whole-model refresh keeps the changes.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, mergedCatalog, adminCatalog} from "./catalogs.mjs";
import {mountHook, sent} from "./harness.mjs";
import {feedback, keepUnsavedEdits} from "../../priv/js/ash_a2ui_protocol.js";

const {
  editCount,
  waitingReviews,
  countText,
  saveDecision,
  thenOffered,
  confirmTexts,
  writeDraft,
  discardEdits,
  saveSpec,
  EDITS_PATH,
} = adminCatalog;

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

// --- the pure helpers -------------------------------------------------------

const reviews = [
  {component: "facts", field: "title"},
  {component: "facts", field: "amount"},
];

const record = (title, amount, extra = {}) => ({
  id: "s1",
  _review_title: {state: title},
  _review_amount: {state: amount},
  ...extra,
});

test("a field waits while its review is pending or missing", () => {
  assert.equal(waitingReviews({reviews, record: record("pending", "missing")}), 2);
  assert.equal(waitingReviews({reviews, record: record("reviewed", "missing")}), 1);
  assert.equal(waitingReviews({reviews, record: record("reviewed", "reviewed")}), 0);
  assert.equal(waitingReviews({reviews}), 0);
});

test("with editReviews, a field with a change no longer waits", () => {
  const edits = {facts: {recordId: "s1", values: {title: "Yearly fee"}}};
  const props = {reviews, record: record("pending", "pending"), edits};
  assert.equal(waitingReviews(props), 2);
  assert.equal(waitingReviews({...props, editReviews: true}), 1);
});

test("the changes are counted across cards", () => {
  assert.equal(editCount(undefined), 0);
  assert.equal(editCount({}), 0);
  assert.equal(
    editCount({facts: {values: {title: "x", amount: "1"}}, terms: {values: {due: "2027-01-01"}}}),
    3,
  );
});

test("a counted text takes its form for one and puts the count in", () => {
  assert.equal(countText("%{count} to check", "1 to check", 3), "3 to check");
  assert.equal(countText("%{count} to check", "1 to check", 1), "1 to check");
  assert.equal(countText("%{count} to check", undefined, 1), "1 to check");
  assert.equal(countText(undefined, undefined, 2), "");
});

const confirm = {
  title: "Save with %{count} unchecked?",
  titleOne: "Save with 1 unchecked?",
  message: "%{count} still wait.",
  cancelLabel: "Cancel",
  saveLabel: "Save progress",
  thenLabel: "Save and finish",
  then: true,
  thenVisible: "review_open",
  thenWhenClear: false,
};

test("Save opens the dialog while fields wait, else saves", () => {
  const waiting = {reviews, record: record("pending", "reviewed", {review_open: true}), confirm};
  assert.equal(saveDecision(waiting), "confirm");

  const clear = {reviews, record: record("reviewed", "reviewed", {review_open: true}), confirm};
  assert.equal(saveDecision(clear), "save");
  assert.equal(saveDecision({...clear, confirm: {...confirm, thenWhenClear: true}}), "then");

  // without a confirm, Save always saves
  assert.equal(saveDecision({reviews, record: record("pending", "pending")}), "save");
});

test("the dialog offers its second choice only where the record offers it", () => {
  const props = {reviews, record: record("pending", "pending", {review_open: true}), confirm};
  assert.equal(thenOffered(props), true);
  assert.deepEqual(confirmTexts(props), {
    count: 2,
    title: "Save with 2 unchecked?",
    message: "2 still wait.",
    cancelLabel: "Cancel",
    saveLabel: "Save progress",
    thenLabel: "Save and finish",
  });

  const closed = {...props, record: record("pending", "reviewed", {review_open: false})};
  assert.equal(thenOffered(closed), false);
  assert.equal(confirmTexts(closed).thenLabel, "");
  assert.equal(confirmTexts(closed).title, "Save with 1 unchecked?");
});

test("the save envelope carries the choice", () => {
  const action = {action: "save_changes", context: {edits: {"@path": "/ui/edits"}}};
  const spec = saveSpec({action}, "then");
  assert.equal(spec.name, "save_changes");
  assert.deepEqual(spec.context, {edits: {"@path": "/ui/edits"}, choice: "then"});
  assert.equal(saveSpec({}, "save"), null);
});

function fakeModel(initial = {}) {
  const data = structuredClone(initial);
  const walk = (path, create) => {
    const parts = path.split("/").filter(Boolean);
    const last = parts.pop();
    let node = data;
    for (const part of parts) {
      if (node[part] === undefined) {
        if (!create) return [undefined, last];
        node[part] = {};
      }
      node = node[part];
    }
    return [node, last];
  };
  return {
    data,
    get(path) {
      const [node, last] = walk(path, false);
      return node === undefined ? undefined : node[last];
    },
    set(path, value) {
      const [node, last] = walk(path, true);
      if (value === undefined) delete node[last];
      else node[last] = value;
    },
  };
}

test("a draft is written with its record, and dropped when back at the stored value", () => {
  const model = fakeModel({ui: {edit_errors: {facts: {title: "too short"}}}});
  const edit = {component: "facts", field: "title"};

  writeDraft(model, edit, {recordId: "s1", value: "Yearly fee", stored: "Annual fee"});
  assert.deepEqual(model.get(EDITS_PATH), {facts: {recordId: "s1", values: {title: "Yearly fee"}}});
  assert.equal(model.get("/ui/edit_errors/facts/title"), undefined);

  writeDraft(model, edit, {recordId: "s1", value: "Annual fee", stored: "Annual fee"});
  assert.deepEqual(model.get(EDITS_PATH), {});

  // a number is kept as the text the input held
  writeDraft(model, {component: "facts", field: "amount"}, {recordId: "s1", value: 1400, stored: 1200});
  assert.equal(model.get("/ui/edits/facts/values/amount"), "1400");

  discardEdits(model);
  assert.deepEqual(model.get(EDITS_PATH), {});
  assert.deepEqual(model.get("/ui/edit_errors"), {});
});

test("a whole-model refresh keeps the unsaved changes; the server's own write clears them", () => {
  const edits = {facts: {recordId: "s1", values: {title: "Yearly fee"}}};
  const editsOf = (id) => (id === "s1" ? edits : null);
  const messages = [
    {version: "1.0", updateDataModel: {surfaceId: "s1", path: "/", value: {ui: {feedback: {}}, detail: {}}}},
    {version: "1.0", updateDataModel: {surfaceId: "s1", path: "/ui", value: {feedback: {}}}},
    {version: "1.0", updateDataModel: {surfaceId: "s1", path: "/ui/edits", value: {}}},
    {version: "1.0", updateDataModel: {surfaceId: "s2", path: "/", value: {}}},
  ];

  const [whole, ui, cleared, other] = keepUnsavedEdits(messages, editsOf);
  assert.deepEqual(whole.updateDataModel.value.ui.edits, edits);
  assert.deepEqual(whole.updateDataModel.value.detail, {});
  assert.deepEqual(ui.updateDataModel.value.edits, edits);
  assert.equal(cleared, messages[2]);
  assert.equal(other, messages[3]);
  // the input messages are not modified
  assert.equal(messages[0].updateDataModel.value.ui.edits, undefined);
});

// --- the elements ----------------------------------------------------------

const facts = {
  edit: {
    component: "facts",
    field: "title",
    recordId: {"@path": "/detail/statement/id"},
    input: "text",
  },
  editValue: {"@path": "/detail/statement/_edit_title"},
  editVisible: {"@path": "/detail/statement/_editable_facts"},
  editDraft: {"@path": "/ui/edits/facts/values/title"},
  editError: {"@path": "/ui/edit_errors/facts/title"},
};

const bar = {
  id: "save_bar",
  component: "saveBar",
  message: "You have unsaved changes",
  messageWaiting: "Reviewing the statement",
  status: "%{count} to check",
  statusOne: "1 to check",
  saveLabel: "Save changes",
  discardLabel: "Discard changes",
  edits: {"@path": "/ui/edits"},
  record: {"@path": "/detail/statement"},
  reviews: [{component: "facts", field: "title"}],
  editReviews: true,
  action: {
    action: "save_changes",
    context: {edits: {"@path": "/ui/edits"}, recordId: {"@path": "/detail/statement/id"}},
  },
  confirm,
};

async function mountPage({editable = true, review = "pending", reviewOpen = true, editReviews = true} = {}) {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [
          {id: "root", component: "Column", children: ["title", "save_bar"]},
          {
            id: "title",
            component: "fieldDisplay",
            label: "Title",
            value: {"@path": "/detail/statement/title"},
            ...facts,
          },
          {...bar, editReviews},
        ],
        dataModel: {
          detail: {
            statement: {
              id: "s1",
              title: "Annual fee",
              _edit_title: "Annual fee",
              _editable_facts: editable,
              _review_title: {state: review, stateLabel: "Not reviewed"},
              review_open: reviewOpen,
            },
          },
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
  const saveBar = deep(element, "ash-admin-save-bar");
  assert.ok(field, "the field renders");
  assert.ok(saveBar, "the bar renders");
  return {hook, field, saveBar, model: hook.processor.getSurface("s1").dataModel};
}

const valueControl = (field) => field.renderRoot.querySelector("[data-a2ui-edit]");
const input = (field) => field.renderRoot.querySelector("[data-a2ui-edit-input]");

async function type(field, value, key) {
  field.openEdit();
  await settle();
  const control = input(field);
  assert.ok(control, "the input opens");
  control.value = value;
  if (key) control.dispatchEvent(new KeyboardEvent("keydown", {key, bubbles: true}));
  else control.dispatchEvent(new Event("blur"));
  await settle();
}

test("a field the record offers editing on opens as an input, and is read-only otherwise", async () => {
  const {field} = await mountPage();
  assert.ok(valueControl(field), "the value is a control");
  valueControl(field).click();
  await settle();
  assert.ok(input(field), "a click opens the input");
  assert.equal(input(field).value, "Annual fee");

  const locked = await mountPage({editable: false});
  assert.equal(valueControl(locked.field), null);
  assert.equal(input(locked.field), null);
});

test("Enter keeps a change as a draft, and the bar shows with the count", async () => {
  const {field, saveBar, model} = await mountPage();
  assert.equal(saveBar.hidden, true, "no change, no bar");

  await type(field, "Yearly fee", "Enter");
  assert.deepEqual(model.get("/ui/edits"), {facts: {recordId: "s1", values: {title: "Yearly fee"}}});
  assert.equal(input(field), null, "the input closes");
  assert.equal(valueControl(field).textContent.trim(), "Yearly fee");

  await settle();
  assert.equal(saveBar.hidden, false);
  // the only field under review is being edited, so nothing waits
  assert.equal(saveBar.renderRoot.querySelector(".bar").dataset.waiting, "0");
  assert.match(saveBar.renderRoot.textContent, /You have unsaved changes/);
});

test("Escape drops the change; leaving the input keeps it", async () => {
  const {field, model} = await mountPage();
  await type(field, "Yearly fee", "Escape");
  assert.equal(model.get("/ui/edits"), undefined);

  await type(field, "Yearly fee");
  assert.equal(model.get("/ui/edits/facts/values/title"), "Yearly fee");
});

test("Discard drops every change and hides the bar", async () => {
  const {field, saveBar, model} = await mountPage();
  await type(field, "Yearly fee", "Enter");
  saveBar.onDiscard();
  await settle();
  assert.deepEqual(model.get("/ui/edits"), {});
  assert.equal(saveBar.hidden, true);
});

test("Save sends save_changes with the changes when nothing waits", async () => {
  const {hook, field, saveBar} = await mountPage();
  await type(field, "Yearly fee", "Enter");
  saveBar.onSave();
  await settle();

  const call = sent(hook).at(-1).callAgentFunction.callFunction.args;
  assert.equal(call.name, "save_changes");
  assert.equal(call.context.choice, "save");
  assert.deepEqual(call.context.edits, {facts: {recordId: "s1", values: {title: "Yearly fee"}}});
  assert.equal(call.context.recordId, "s1");
});

test("the bar is busy while its save is out, and ready again on the outcome", async () => {
  const {hook, field, saveBar} = await mountPage();
  await type(field, "Yearly fee", "Enter");
  saveBar.onSave();
  await settle();
  assert.equal(saveBar.busy(), true);

  // A second Save while the first is out sends nothing.
  const before = sent(hook).length;
  saveBar.onSave();
  await settle();
  assert.equal(sent(hook).length, before);

  // The outcome settles it, as the server's success writes it.
  hook.processMessages([
    {version: "1.0", updateDataModel: {surfaceId: "s1", path: "/ui/edits", value: {}}},
    {version: "1.0", updateDataModel: {surfaceId: "s1", path: "/ui/feedback", value: feedback("success", "Changes saved.")}},
  ]);
  await settle();
  assert.equal(saveBar.busy(), false);

  // The next change saves again.
  await type(field, "Annual levy", "Enter");
  saveBar.onSave();
  await settle();
  assert.equal(sent(hook).length, before + 1);
});

test("while fields wait, Save opens the dialog; its choices send save or then", async () => {
  // without editReviews, the edited title still waits
  const {hook, field, saveBar} = await mountPage({editReviews: false});
  await type(field, "Yearly fee", "Enter");
  const before = sent(hook).length;

  saveBar.onSave();
  await settle();
  assert.equal(saveBar.confirmOpen(), true);
  assert.equal(sent(hook).length, before, "nothing is sent while the dialog asks");

  saveBar.closeConfirm();
  await settle();
  assert.equal(saveBar.confirmOpen(), false);
  assert.equal(sent(hook).length, before, "Cancel sends nothing");

  saveBar.onSave();
  await settle();
  saveBar.choose("then");
  await settle();
  assert.equal(sent(hook).at(-1).callAgentFunction.callFunction.args.context.choice, "then");
});
