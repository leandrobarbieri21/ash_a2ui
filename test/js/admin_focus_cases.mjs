// The admin catalog's focus handling (the ConfirmDialog trap, the prompt
// dialog's trap and focus restore, the calendar keeping its focused day) and
// the elements an admin surface's inputs render as, run once per DOM mode:
// catalogs.mjs builds the elements over the pinned
// A2uiLitElement (its own shadow root), light_dom_catalogs.mjs over one whose
// createRenderRoot() returns `this` (light DOM, the upstream default after
// 0.15.0). Each mode is its own test file, so each runs in its own process
// and defines the tags once.

import test from "node:test";
import assert from "node:assert/strict";

import {mountHook, sent} from "./harness.mjs";
import {readJson} from "./support.mjs";
import {feedback} from "../../priv/js/ash_a2ui_protocol.js";

async function settle() {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

// querySelector through every open shadow root.
function deep(root, selector) {
  const found = root.querySelector(selector);
  if (found) return found;
  for (const node of root.querySelectorAll("*")) {
    const inner = node.shadowRoot && deep(node.shadowRoot, selector);
    if (inner) return inner;
  }
  return null;
}

// The focused element, through every open shadow root. Compare nodes with
// assert.ok(a === b): assert.equal's failure message inspects a happy-dom
// node's whole object graph and never finishes.
function deepActive() {
  let active = document.activeElement;
  for (;;) {
    const next = active?.shadowRoot?.activeElement;
    if (!next || next === active) return active;
    active = next;
  }
}

// Presses `key` where focus is, the way the browser delivers a keydown.
function press(key, {shiftKey = false} = {}) {
  const event = new KeyboardEvent("keydown", {key, shiftKey, bubbles: true, composed: true, cancelable: true});
  deepActive().dispatchEvent(event);
  return event;
}

const buttonLabelled = (root, label) =>
  [...root.querySelectorAll("button")].find((button) => button.textContent.trim() === label);

export function focusCases({mode, admin, mergedCatalog}) {
  const lightDom = mode === "light DOM";

  function gridSurface(hook, rowAction, extra = []) {
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
              columns: [{label: "Title", path: "title"}],
              rows: {"@path": "/rows"},
              rowId: "id",
              rowActions: [rowAction],
              ...(extra.length ? {children: extra.map((c) => c.id)} : {}),
            },
            ...extra,
          ],
          dataModel: {rows: [{id: "r1", title: "One"}], ui: {feedback: feedback()}},
        },
      },
    ]);
    assert.deepEqual(sent(hook), [], "the surface applies");
  }

  async function render(hook) {
    const element = document.createElement("a2ui-surface");
    document.body.replaceChildren(element);
    element.surface = hook.processor.getSurface("s1");
    await settle();
    return element;
  }

  test(`${mode}: the admin elements render into ${lightDom ? "light DOM" : "their own shadow root"}`, async () => {
    const hook = mountHook({catalogs: [mergedCatalog, admin]});
    gridSurface(hook, {label: "Close", action: "invoke", context: {action: "close"}});
    const grid = deep(await render(hook), "ash-admin-data-grid");
    assert.ok(grid, "the grid renders");
    assert.equal(grid.renderRoot === grid, lightDom);
    assert.equal(grid.shadowRoot === null, lightDom);
  });

  test(`${mode}: an admin surface's TextField and ChoicePicker render as the admin elements`, async () => {
    // The two inputs exactly as the encoder emits them on an admin surface
    // (a recorded probe fixture): no @catalogId, so they resolve from the
    // admin catalog, the surface's own.
    const {messages} = readJson("priv/js/probe/fixtures/manifest_tasks_admin_payload.json");
    const recorded = messages.find((message) => message.createSurface).createSurface;
    const field = recorded.components.find((component) => component.component === "TextField");
    const picker = recorded.components.find((component) => component.component === "ChoicePicker");
    assert.equal("@catalogId" in field, false, "the encoder leaves the TextField unqualified");
    assert.equal("@catalogId" in picker, false, "the encoder leaves the ChoicePicker unqualified");

    const hook = mountHook({catalogs: [mergedCatalog, admin]});
    hook.processMessages([
      {
        version: "1.0",
        createSurface: {
          surfaceId: "s1",
          catalogId: admin.id,
          components: [
            {id: "root", component: "entityPage", title: "Tasks", children: [field.id, picker.id]},
            field,
            picker,
          ],
          dataModel: recorded.dataModel,
        },
      },
    ]);
    assert.deepEqual(sent(hook), [], "the surface applies");
    const surface = await render(hook);

    const textField = deep(surface, "ash-admin-textfield");
    assert.ok(textField, "the TextField is the admin element");
    assert.ok(deep(surface, "ash-admin-choicepicker"), "the ChoicePicker is the admin element");
    assert.equal(deep(surface, "ash-a2ui-textfield"), null);
    assert.equal(deep(surface, "ash-a2ui-choicepicker"), null);
    assert.ok(textField.renderRoot.querySelector("label"), "the admin TextField draws a real label");
  });

  test(`${mode}: Tab and Shift+Tab stay inside the open ConfirmDialog, Escape restores focus`, async () => {
    const hook = mountHook({catalogs: [mergedCatalog, admin]});
    gridSurface(hook, {
      label: "Delete",
      action: "invoke",
      destructive: true,
      context: {action: "destroy", recordId: {"@path": "id"}},
    });
    const surface = await render(hook);
    const grid = deep(surface, "ash-admin-data-grid");

    const opener = deep(surface, "[data-a2ui-action='destroy'] button");
    assert.ok(opener, "the row's Delete button renders");
    opener.focus();
    opener.click();
    await settle();

    const dialog = deep(surface, "ash-admin-confirm-dialog");
    assert.ok(dialog?.open, "the ConfirmDialog opens");
    const root = dialog.renderRoot;
    const heading = root.querySelector("[data-dialog-heading]");
    const cancel = buttonLabelled(root, "Cancel");
    const confirm = buttonLabelled(root, "Delete");
    assert.ok(deepActive() === heading, "the heading has focus once open");

    // From the heading (outside the Tab cycle), Tab lands on the first
    // control and Shift+Tab on the last, never outside the dialog.
    assert.equal(press("Tab").defaultPrevented, true);
    assert.ok(deepActive() === cancel, "focus on cancel");

    heading.focus();
    assert.equal(press("Tab", {shiftKey: true}).defaultPrevented, true);
    assert.ok(deepActive() === confirm, "focus on confirm");

    // Past the last control Tab wraps to the first, and back.
    assert.equal(press("Tab").defaultPrevented, true);
    assert.ok(deepActive() === cancel, "focus on cancel");
    assert.equal(press("Tab", {shiftKey: true}).defaultPrevented, true);
    assert.ok(deepActive() === confirm, "focus on confirm");

    // Between controls the browser moves focus itself.
    cancel.focus();
    assert.equal(press("Tab").defaultPrevented, false);

    press("Escape");
    await settle();
    assert.equal(sent(hook).length, 0, "cancelling invokes nothing");
    assert.ok(deepActive() === opener, "focus returns to the row's Delete button");
  });

  test(`${mode}: the ConfirmDialog draws the text the server sent, and a body only when sent`, async () => {
    const open = async (entry) => {
      const hook = mountHook({catalogs: [mergedCatalog, admin]});
      gridSurface(hook, {action: "invoke", destructive: true, ...entry});
      const surface = await render(hook);
      deep(surface, `[data-a2ui-action='${entry.context.action}'] button`).click();
      await settle();
      return deep(surface, "ash-admin-confirm-dialog").renderRoot;
    };

    const destroy = await open({
      label: "Delete",
      context: {action: "destroy", recordId: {"@path": "id"}},
      confirmTitle: "Supprimer cet enregistrement ?",
      confirmBody: "Cette action est irréversible.",
    });
    assert.equal(destroy.querySelector("[data-dialog-heading]").textContent.trim(), "Supprimer cet enregistrement ?");
    assert.equal(destroy.querySelector(".dialog-body").textContent.trim(), "Cette action est irréversible.");

    const declared = await open({
      label: "Deactivate",
      context: {action: "deactivate", recordId: {"@path": "id"}},
      confirmTitle: "Deactivate this record?",
    });
    assert.equal(declared.querySelector("[data-dialog-heading]").textContent.trim(), "Deactivate this record?");
    assert.equal(declared.querySelector(".dialog-body"), null, "no body was sent, so none is drawn");
    assert.ok(buttonLabelled(declared, "Deactivate"), "the confirm control reads the action's label");
  });

  test(`${mode}: the prompt dialog's trap and focus restore read the focused control`, async () => {
    const hook = mountHook({catalogs: [mergedCatalog, admin]});
    gridSurface(
      hook,
      {
        label: "Rename",
        action: "invoke",
        context: {action: "rename", recordId: {"@path": "id"}},
        prompt: {content: "rename_form", title: "Rename"},
      },
      [{id: "rename_form", component: "Text", text: "New name"}],
    );
    const surface = await render(hook);
    const grid = deep(surface, "ash-admin-data-grid");

    const opener = deep(surface, "[data-a2ui-action='rename'] button");
    opener.focus();
    opener.click();
    await settle();

    const heading = grid.renderRoot.querySelector("[data-prompt-heading]");
    assert.ok(heading, "the prompt dialog opens");
    const last = grid.lastPromptButton();
    assert.ok(last, "the prompt has its buttons");

    // Tab from the last button wraps to the heading; Shift+Tab from the
    // heading to the last button.
    last.focus();
    assert.equal(press("Tab").defaultPrevented, true);
    assert.ok(deepActive() === heading, "focus on heading");
    assert.equal(press("Tab", {shiftKey: true}).defaultPrevented, true);
    assert.ok(deepActive() === last, "focus on last");

    press("Escape");
    await settle();
    assert.ok(grid.renderRoot.querySelector("[data-prompt-heading]") === null, "the prompt closes");
    assert.ok(deepActive() === opener, "focus returns to the row's Rename button");
  });

  test(`${mode}: a calendar repaint keeps keyboard focus on the focused day`, async () => {
    const hook = mountHook({catalogs: [mergedCatalog, admin], actionTimeoutMs: 0});
    const window = (anchor, marks = []) => ({granularity: "month", anchor, selected: "", marks, label: anchor});
    hook.processMessages([
      {
        version: "1.0",
        createSurface: {
          surfaceId: "s1",
          catalogId: admin.id,
          components: [
            {id: "root", component: "Column", children: ["cal"]},
            {
              id: "cal",
              component: "calendarView",
              label: "Visits",
              granularity: "month",
              window: {"@path": "/window"},
              windowAction: {name: "query", context: {component: "visits"}},
            },
          ],
          dataModel: {window: window("2026-11-01"), ui: {feedback: feedback()}},
        },
      },
    ]);
    const surface = await render(hook);
    const view = deep(surface, "ash-admin-calendar-view");
    const calendar = view.calendarElement();
    assert.ok(calendar, "the calendar grid renders");

    calendar.focusDateInMonth(new Date(2026, 10, 12));
    assert.equal(deepActive()?.dataset?.date, "2026-11-12");

    // New marks repaint the grid; the focused day keeps focus.
    hook.processMessages([
      {
        version: "1.0",
        updateDataModel: {surfaceId: "s1", path: "/window", value: window("2026-11-01", [{date: "2026-11-03", count: 2}])},
      },
    ]);
    await settle();
    assert.equal(deepActive()?.dataset?.date, "2026-11-12", "focus stays on the day");
  });
}
