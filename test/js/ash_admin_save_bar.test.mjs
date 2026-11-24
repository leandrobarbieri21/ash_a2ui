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
  reviewCounts,
  rowsWaiting,
  countText,
  saveDecision,
  saveBarState,
  showsWhileWaiting,
  choiceSends,
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

  const changed = {facts: {recordId: "s1", values: {title: "x"}}};
  const clear = {reviews, record: record("reviewed", "reviewed", {review_open: true}), confirm, edits: changed};
  assert.equal(saveDecision(clear), "save");
  assert.equal(saveDecision({...clear, confirm: {...confirm, thenWhenClear: true}}), "then");

  // without a confirm, Save saves the changes
  const edits = {facts: {recordId: "s1", values: {title: "x"}}};
  assert.equal(saveDecision({reviews, record: record("pending", "pending"), edits}), "save");
});

test("3.14: with no change, Save opens the dialog while fields wait and else sends nothing", () => {
  const waiting = {reviews, record: record("pending", "reviewed", {review_open: true}), confirm};
  assert.equal(saveDecision(waiting), "confirm");

  // no dialog to open and no change: nothing to send
  assert.equal(saveDecision({reviews, record: record("pending", "pending")}), "none");
  const clear = {reviews, record: record("reviewed", "reviewed", {review_open: true}), confirm};
  assert.equal(saveDecision(clear), "none");
  // ...unless saving finishes the review
  assert.equal(saveDecision({...clear, confirm: {...confirm, thenWhenClear: true}}), "then");

  // the dialog's save choice sends only a change; its then choice always sends
  assert.equal(choiceSends(waiting, "save"), false);
  assert.equal(choiceSends(waiting, "then"), true);
  assert.equal(choiceSends({...waiting, edits: {facts: {values: {title: "x"}}}}, "save"), true);
});

test("3.14: showWhileWaiting is true, or the record's field that is true", () => {
  assert.equal(showsWhileWaiting({}), false);
  assert.equal(showsWhileWaiting({showWhileWaiting: false}), false);
  assert.equal(showsWhileWaiting({showWhileWaiting: true}), true);
  assert.equal(showsWhileWaiting({showWhileWaiting: "open", record: {open: true}}), true);
  assert.equal(showsWhileWaiting({showWhileWaiting: "open", record: {open: false}}), false);
  assert.equal(showsWhileWaiting({showWhileWaiting: "open"}), false);
});

test("3.14: what the bar draws, with and without a change, while fields wait and once none does", () => {
  const base = {
    reviews,
    message: "You have unsaved changes",
    messageWaiting: "Reviewing the statement",
    status: "%{count} to check",
    statusOne: "1 to check",
  };

  // the 3.11 rule: no change, no bar, even while fields wait
  assert.equal(saveBarState({...base, record: record("pending", "pending")}).shown, false);

  // showWhileWaiting: fields wait, no change: the bar, without Discard
  const waiting = {...base, showWhileWaiting: true, record: record("pending", "missing")};
  assert.deepEqual(saveBarState(waiting), {
    shown: true,
    edits: 0,
    waiting: 2,
    reviewed: 0,
    message: "Reviewing the statement",
    status: "2 to check",
    statusReviewed: "",
    discard: false,
  });

  // a change: Discard too
  const edited = {...waiting, edits: {facts: {recordId: "s1", values: {title: "x"}}}};
  assert.equal(saveBarState(edited).discard, true);
  assert.equal(saveBarState(edited).edits, 1);

  // nothing waits and nothing changed: no bar
  const done = {...base, showWhileWaiting: true, record: record("reviewed", "reviewed")};
  assert.equal(saveBarState(done).shown, false);
  // a change with nothing waiting: the plain message, no tag
  const doneEdited = {...done, edits: edited.edits};
  assert.equal(saveBarState(doneEdited).shown, true);
  assert.equal(saveBarState(doneEdited).message, "You have unsaved changes");
  assert.equal(saveBarState(doneEdited).status, "");

  // a record with no review fields at all: no bar
  assert.equal(saveBarState({...base, showWhileWaiting: true, record: {id: "s1"}}).shown, false);
});

test("3.17: a field is reviewed once its review is, or, with editReviews, while it has a change", () => {
  const edits = {facts: {recordId: "s1", values: {title: "x"}}};
  assert.deepEqual(reviewCounts({reviews, record: record("pending", "missing")}), {waiting: 2, reviewed: 0, open: true});
  assert.deepEqual(reviewCounts({reviews, record: record("reviewed", "pending")}), {waiting: 1, reviewed: 1, open: true});
  // a change reviews a waiting field only with editReviews
  assert.deepEqual(reviewCounts({reviews, edits, record: record("pending", "pending")}), {
    waiting: 2,
    reviewed: 0,
    open: true,
  });
  assert.deepEqual(reviewCounts({reviews, edits, editReviews: true, record: record("pending", "reviewed")}), {
    waiting: 0,
    reviewed: 2,
    open: true,
  });
  // a change to a field already reviewed counts it once
  assert.deepEqual(reviewCounts({reviews, edits, editReviews: true, record: record("reviewed", "pending")}), {
    waiting: 1,
    reviewed: 1,
    open: true,
  });
  // every review saved reviewed: the review is closed
  assert.deepEqual(reviewCounts({reviews, record: record("reviewed", "reviewed")}), {
    waiting: 0,
    reviewed: 2,
    open: false,
  });
  // a field with no review counts nowhere
  assert.deepEqual(reviewCounts({reviews, record: {id: "s1"}}), {waiting: 0, reviewed: 0, open: false});
});

test("3.17: the reviewed tag shows while the review is open and a field is reviewed", () => {
  const base = {
    reviews,
    showWhileWaiting: true,
    editReviews: true,
    message: "You have unsaved changes",
    messageWaiting: "Reviewing the statement",
    status: "%{count} to check",
    statusOne: "1 to check",
    statusReviewed: "%{count} checked",
    statusReviewedOne: "1 checked!",
  };
  const edits = {facts: {recordId: "s1", values: {title: "x"}}};

  // nothing reviewed yet: no tag
  assert.equal(saveBarState({...base, record: record("pending", "missing")}).statusReviewed, "");
  // one reviewed: its form for one, beside the waiting one
  const one = saveBarState({...base, record: record("reviewed", "missing")});
  assert.equal(one.status, "1 to check");
  assert.equal(one.statusReviewed, "1 checked!");
  assert.equal(one.reviewed, 1);
  // a change reviews the other: two reviewed, none waiting, the review still open
  const amount = {facts: {recordId: "s1", values: {amount: 3}}};
  const two = saveBarState({...base, edits: amount, record: record("reviewed", "missing")});
  assert.equal(two.status, "");
  assert.equal(two.statusReviewed, "2 checked");
  // every review saved reviewed: a later change shows no tag
  assert.equal(saveBarState({...base, edits, record: record("reviewed", "reviewed")}).statusReviewed, "");
  // without statusReviewed: no tag
  const {statusReviewed: _omit, ...plain} = base;
  assert.equal(saveBarState({...plain, record: record("reviewed", "pending")}).statusReviewed, "");
});

test("3.16: the table rows still waiting on the record count with the fields", () => {
  const rows = (waiting) => ({_review_rows: {waiting}});
  assert.equal(rowsWaiting(rows(3)), 3);
  assert.equal(rowsWaiting({}), 0);
  assert.equal(rowsWaiting(rows("2")), 0);
  assert.equal(rowsWaiting(rows(-1)), 0);
  assert.equal(rowsWaiting(null), 0);

  // two lines wait beside one field
  assert.equal(waitingReviews({reviews, record: record("pending", "reviewed", rows(2))}), 3);
  // every field reviewed, lines still waiting: the bar stays, counting them
  const base = {reviews, showWhileWaiting: true, status: "%{count} to check", statusOne: "1 to check"};
  const linesOnly = saveBarState({...base, record: record("reviewed", "reviewed", rows(1))});
  assert.equal(linesOnly.shown, true);
  assert.equal(linesOnly.status, "1 to check");
  // and Save asks first while they wait
  assert.equal(saveDecision({...base, confirm, record: record("reviewed", "reviewed", rows(1))}), "confirm");
  // none left: the bar goes
  assert.equal(saveBarState({...base, record: record("reviewed", "reviewed", rows(0))}).shown, false);
});

test("3.17: the rows reviewed on the record count with the fields, and rows waiting keep the review open", () => {
  const rows = (waiting, reviewed) => ({_review_rows: {waiting, reviewed}});
  const base = {
    reviews,
    showWhileWaiting: true,
    status: "%{count} to check",
    statusReviewed: "%{count} checked",
  };
  // two lines checked, one waiting, beside one field checked and one waiting
  assert.deepEqual(reviewCounts({reviews, record: record("reviewed", "pending", rows(1, 2))}), {
    waiting: 2,
    reviewed: 3,
    open: true,
  });
  // every field reviewed, a line still waiting: the review is open, both tags
  const lineLeft = saveBarState({...base, record: record("reviewed", "reviewed", rows(1, 2))});
  assert.equal(lineLeft.status, "1 to check");
  assert.equal(lineLeft.statusReviewed, "4 checked");
  // all done: closed, no tag
  assert.equal(saveBarState({...base, record: record("reviewed", "reviewed", rows(0, 3))}).statusReviewed, "");
  // a bad count counts nowhere
  assert.equal(reviewCounts({reviews, record: record("pending", "pending", rows(0, "3"))}).reviewed, 0);
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

async function mountPage({
  editable = true,
  review = "pending",
  reviewOpen = true,
  editReviews = true,
  showWhileWaiting = undefined,
  statusReviewed = undefined,
} = {}) {
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
          {
            ...bar,
            editReviews,
            ...(showWhileWaiting === undefined ? {} : {showWhileWaiting}),
            ...(statusReviewed === undefined ? {} : {statusReviewed}),
          },
        ],
        dataModel: {
          detail: {
            statement: {
              id: "s1",
              title: "Annual fee",
              _edit_title: "Annual fee",
              _editable_facts: editable,
              correctable: editable,
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

// --- 3.14: the bar while reviews wait ----------------------------------------

const buttons = (saveBar) => [...saveBar.renderRoot.querySelectorAll("button")].map((b) => b.textContent.trim());

test("3.14: while values wait, the bar shows before any change, with Save and no Discard", async () => {
  const {saveBar} = await mountPage({showWhileWaiting: "correctable"});
  assert.equal(saveBar.hidden, false, "the bar shows from the first render");
  const barEl = saveBar.renderRoot.querySelector(".bar");
  assert.equal(barEl.dataset.editCount, "0");
  assert.equal(barEl.dataset.waiting, "1");
  assert.match(saveBar.renderRoot.textContent, /Reviewing the statement/);
  assert.match(saveBar.renderRoot.textContent, /1 to check/);
  assert.deepEqual(buttons(saveBar), ["Save changes"]);
});

test("3.17: the reviewed tag follows the review, after the waiting one", async () => {
  const {field, saveBar} = await mountPage({showWhileWaiting: "correctable", statusReviewed: "%{count} checked"});
  const tags = () =>
    [...saveBar.renderRoot.querySelectorAll(".am-badge")].map((tag) => [tag.dataset.tone, tag.textContent.trim()]);
  assert.deepEqual(tags(), [["warning", "1 to check"]], "nothing reviewed yet: no reviewed tag");

  // a change reviews the field: the reviewed tag, nothing waiting
  await type(field, "Yearly fee", "Enter");
  assert.deepEqual(tags(), [["success", "1 checked"]]);
  assert.equal(saveBar.renderRoot.querySelector(".bar").dataset.reviewed, "1");

  // discarded: back to waiting
  saveBar.onDiscard();
  await settle();
  assert.deepEqual(tags(), [["warning", "1 to check"]]);
});

test("3.14: a change adds Discard; discarding keeps the bar while values wait", async () => {
  const {field, saveBar} = await mountPage({showWhileWaiting: "correctable", editReviews: false});
  await type(field, "Yearly fee", "Enter");
  assert.deepEqual(buttons(saveBar), ["Discard changes", "Save changes"]);

  saveBar.onDiscard();
  await settle();
  assert.equal(saveBar.hidden, false);
  assert.deepEqual(buttons(saveBar), ["Save changes"]);
});

test("3.14: the bar stays hidden where the record's field is false, and once nothing waits", async () => {
  const locked = await mountPage({showWhileWaiting: "correctable", editable: false});
  assert.equal(locked.saveBar.hidden, true);

  const reviewed = await mountPage({showWhileWaiting: "correctable", review: "reviewed"});
  assert.equal(reviewed.saveBar.hidden, true);

  // the last value reviewed (the server writes the record back whole): the bar goes
  const {hook, saveBar, model} = await mountPage({showWhileWaiting: "correctable"});
  assert.equal(saveBar.hidden, false);
  const statement = {...model.get("/detail/statement"), _review_title: {state: "reviewed"}};
  hook.processMessages([
    {version: "1.0", updateDataModel: {surfaceId: "s1", path: "/detail/statement", value: statement}},
  ]);
  await settle();
  assert.equal(saveBar.hidden, true);
});

test("3.14: Save with no change opens the dialog; its save sends nothing, its then sends then", async () => {
  const {hook, saveBar} = await mountPage({showWhileWaiting: "correctable"});
  const before = sent(hook).length;

  saveBar.onSave();
  await settle();
  assert.equal(saveBar.confirmOpen(), true);

  saveBar.choose("save");
  await settle();
  assert.equal(saveBar.confirmOpen(), false, "the dialog closes");
  assert.equal(sent(hook).length, before, "a save with nothing changed sends nothing");
  assert.equal(saveBar.busy(), false);

  saveBar.onSave();
  await settle();
  saveBar.choose("then");
  await settle();
  assert.equal(sent(hook).length, before + 1);
  const call = sent(hook).at(-1).callAgentFunction.callFunction.args;
  assert.equal(call.name, "save_changes");
  assert.equal(call.context.choice, "then");
  assert.equal(call.context.recordId, "s1");
});
