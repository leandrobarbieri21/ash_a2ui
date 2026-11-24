// The stock entityPage draws only the body children that have something to
// show. A blank child (a Column with no children, or whose Texts are all
// empty: the action result panel before a generic action returns text)
// holds no gap in the page's column; it is drawn as soon as its text has
// words, and goes again when the text empties.

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

async function mountPage() {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [
          {
            id: "root",
            component: "entityPage",
            title: "Dossier",
            children: ["section_facts", "section_empty", "section_blank", "action_result_panel"],
          },
          {id: "section_facts", component: "Column", children: ["facts_text"]},
          {id: "facts_text", component: "Text", text: "Facts"},
          {id: "section_empty", component: "Column", children: []},
          {id: "section_blank", component: "Column", children: ["blank_text"]},
          {id: "blank_text", component: "Text", text: " "},
          {id: "action_result_panel", component: "Column", children: ["action_result_text"]},
          {id: "action_result_text", component: "Text", text: {"@path": "/ui/feedback/resultText"}},
        ],
        dataModel: {ui: {feedback: feedback()}},
      },
    },
  ]);
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("s1");
  await settle();
  const pageEl = deep(element, "ash-admin-entity-page");
  assert.ok(pageEl, "the page renders");
  return {hook, pageEl};
}

const write = (hook, path, value) =>
  hook.processMessages([{version: "1.0", updateDataModel: {surfaceId: "s1", path, value}}]);

// The ids of the components the page's column draws, in order.
const drawn = (pageEl) =>
  [...pageEl.renderRoot.querySelector(".page-body").children].map(
    (el) => el.id || el.getAttribute("data-a2ui-id") || el.component?.id || el.context?.componentModel?.id || el.tagName,
  );

const body = (pageEl) => pageEl.renderRoot.querySelector(".page-body");

// The text a node draws, through the shadow roots of the parts inside it.
function text(node) {
  if (node.nodeType === Node.TEXT_NODE) return node.textContent;
  const own = [...(node.shadowRoot?.childNodes ?? []), ...node.childNodes];
  return own.map(text).join("");
}

test("a blank child takes no place in the page's column", async () => {
  const {pageEl} = await mountPage();
  // Only the section with words is drawn: the empty Column, the Column of a
  // blank Text and the result panel with no text are not.
  assert.equal(body(pageEl).children.length, 1, `drawn: ${drawn(pageEl).join(", ")}`);
  assert.match(text(body(pageEl)), /Facts/);
});

test("the result panel is drawn while an action's text has words, and goes when it empties", async () => {
  const {hook, pageEl} = await mountPage();
  assert.equal(body(pageEl).children.length, 1);

  write(hook, "/ui/feedback", feedback("success", "Done", {resultText: "3 contracts renewed"}));
  await settle();
  assert.equal(body(pageEl).children.length, 2);
  assert.match(text(body(pageEl)), /3 contracts renewed/);

  write(hook, "/ui/feedback", feedback());
  await settle();
  assert.equal(body(pageEl).children.length, 1);
});
