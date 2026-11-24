// `data-a2ui-pending` on the hook's container while an ashAction call is
// unanswered, and a visible error for a message the processor cannot apply.

import "./dom.mjs";
import test from "node:test";
import assert from "node:assert/strict";

import {ASH_A2UI_CATALOG_ID, feedback} from "../../priv/js/ash_a2ui_protocol.js";
import {click, mountHook, sent, tick} from "./harness.mjs";
import {BASIC_CATALOG_ID} from "./support.mjs";

const PENDING = "data-a2ui-pending";

function surface(version = "1.0") {
  return {
    version,
    createSurface: {
      surfaceId: "s1",
      catalogId: BASIC_CATALOG_ID,
      components: [
        {id: "root", component: "Column", children: ["submit"]},
        {
          id: "submit",
          component: "Button",
          child: "label",
          action: {
            functionCall: {
              "@call": "ashAction",
              catalogId: ASH_A2UI_CATALOG_ID,
              args: {name: "submit_form", sourceComponentId: "submit", context: {}},
            },
          },
        },
        {id: "label", component: "Text", text: "Save"},
      ],
      dataModel: {ui: {feedback: feedback()}},
    },
  };
}

// The hook on a real element, so attributes and children exist.
function mount(options) {
  const hook = mountHook(options);
  hook.el = document.createElement("div");
  return hook;
}

const answer = (functionCallId, body) => ({
  version: "1.0",
  agentFunctionResponse: {functionCallId, ...body},
});

test("the container is pending from the click until the agent's answer, and clean after", async () => {
  const hook = mount();
  hook.processMessages([surface()]);
  assert.equal(hook.el.hasAttribute(PENDING), false);

  const done = click(hook, "s1", "submit");
  await tick();
  assert.equal(hook.el.getAttribute(PENDING), "true", "set while the call is out");

  const {functionCallId} = sent(hook)[0].callAgentFunction;
  hook.processMessages([answer(functionCallId, {value: {kind: "success"}})]);
  await done;
  assert.equal(hook.el.hasAttribute(PENDING), false, "cleared by a success");
});

test("an error answer clears the marker too", async () => {
  const hook = mount();
  hook.processMessages([surface()]);

  const done = click(hook, "s1", "submit");
  await tick();
  assert.equal(hook.el.getAttribute(PENDING), "true");

  const {functionCallId} = sent(hook)[0].callAgentFunction;
  hook.processMessages([answer(functionCallId, {error: {code: "FORBIDDEN", message: "No"}})]);
  await done;
  assert.equal(hook.el.hasAttribute(PENDING), false, "cleared by an error");
});

test("a call that times out clears the marker", async () => {
  const hook = mount({actionTimeoutMs: 20});
  hook.processMessages([surface()]);

  const done = click(hook, "s1", "submit");
  await tick();
  assert.equal(hook.el.getAttribute(PENDING), "true", "set during the slow call");

  await done;
  assert.equal(hook.el.hasAttribute(PENDING), false, "cleared by the timeout");
});

test("the marker stays while any of several calls is out", async () => {
  const hook = mount();
  hook.processMessages([surface()]);
  const surfaceModel = hook.processor.getSurface("s1");
  const query = (page) =>
    hook.runAshAction({name: "query", sourceComponentId: "pager", context: {page}}, {surface: surfaceModel});

  const first = query(1);
  await tick();
  const second = query(2);
  await tick();

  const [one, two] = sent(hook).map((message) => message.callAgentFunction.functionCallId);
  hook.processMessages([answer(one, {value: {}})]);
  await first;
  assert.equal(hook.el.getAttribute(PENDING), "true", "the second call is still out");

  hook.processMessages([answer(two, {value: {}})]);
  await second;
  assert.equal(hook.el.hasAttribute(PENDING), false);
});

test("a malformed message shows an alert instead of a blank surface, and sends the error", () => {
  const hook = mount();
  hook.processMessages([surface("v1.0")]);

  const alert = hook.el.querySelector("[data-a2ui-error]");
  assert.ok(alert, "the failure is on the page");
  assert.equal(alert.getAttribute("role"), "alert");
  assert.match(alert.textContent, /VALIDATION_FAILED/);

  const [error] = sent(hook);
  assert.equal(error.error.code, "VALIDATION_FAILED");
});

test("a surface that then applies cleanly removes the alert", () => {
  const hook = mount();
  hook.processMessages([surface("v1.0")]);
  assert.ok(hook.el.querySelector("[data-a2ui-error]"));

  hook.processMessages([surface()]);
  assert.equal(hook.el.querySelector("[data-a2ui-error]"), null);
});

test("a clean batch shows no alert", () => {
  const hook = mount();
  hook.processMessages([surface()]);
  assert.equal(hook.el.querySelector("[data-a2ui-error]"), null);
});
